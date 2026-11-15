<#
.SYNOPSIS
  Sends this branch's dbo.m_employee rows to the central biometricsAPI (UPSERT).

.DESCRIPTION
  Reads m_employee from the branch database, keeps only rows that changed since the
  last successful run (a hash per EmployeeID is kept in state\employee-hashes.json),
  and posts them in gzip-compressed JSON batches to /api/employees/upsert.
  A batch's hashes are saved only after the API accepts it, so a failed run is simply
  retried by the next run.

.EXAMPLE
  sync-employees.bat              send changed rows
  sync-employees.bat -Full        send every row (server still skips unchanged ones)
  sync-employees.bat -Test        check API URL + key only
  sync-employees.bat -SaveKey     store the API key encrypted for this Windows user
#>
param(
    [switch]$Full,
    [switch]$Test,
    [switch]$SaveKey,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'sync-config.json')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

# Same columns as EmployeeDto on the API. Not sent: BioEmployeeGUID / BranchGUID (assigned
# centrally) and EmployeeGUID (owned by another application).
$Columns = @(
    'EmployeeID', 'EmployeeCode', 'IdCode', 'Surname', 'FirstName', 'MiddleName',
    'NameExtention', 'FullName', 'ResidentialAddress', 'ResidentialZipCode', 'ResidentialTelephone',
    'EmailAddress', 'CellPhone', 'DateOfBirth', 'PlaceOfBirth', 'Sex', 'CivilStatus',
    'CivilStatusOther', 'Citizenship', 'Height', 'Weight', 'BloodType', 'HDMFIdNo', 'PHICIdNo',
    'SSSNo', 'TIN', 'TaxCodeID', 'BankAccountNo', 'DepartmentID', 'PositionID', 'Department',
    'ShiftID', 'HourlyRate', 'MonthlyRate', 'DailyRate', 'DateHired', 'WorkStatus',
    'HDMFEmployee', 'HDMFEmployer', 'DateResigned', 'AllowsLate', 'PHICBracketID', 'SSSBracketID',
    'ProbationaryDate', 'IncludeSSS', 'IncludeHDMF', 'IncludePHIC', 'IncludeTax',
    'ReasonforResignation', 'FinalPayDate', 'EmploymentStatus', 'AllowsUT', 'Allowance',
    'AllowsAbsences', 'Remarks', 'IsSave', 'IsDeleted', 'EncodedByID', 'EncodedOn',
    'IsNoPunch', 'WorkDays'
)

# NOT NULL in the central table: the sync stops if the branch table lacks one of these.
# Any other column the branch table doesn't have is sent as null.
$RequiredColumns = @(
    'EmployeeID', 'ShiftID', 'HourlyRate', 'MonthlyRate', 'DailyRate', 'HDMFEmployee', 'HDMFEmployer',
    'AllowsLate', 'PHICBracketID', 'SSSBracketID', 'IncludeSSS', 'IncludeHDMF', 'IncludePHIC', 'IncludeTax',
    'AllowsUT', 'Allowance', 'AllowsAbsences', 'IsSave', 'IsDeleted', 'EncodedByID'
)

$logDir = Join-Path $PSScriptRoot 'logs'
$stateDir = Join-Path $PSScriptRoot 'state'
$statePath = Join-Path $stateDir 'employee-hashes.json'
New-Item -ItemType Directory -Force -Path $logDir, $stateDir | Out-Null

function Write-Log([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Write-Host $line
    Add-Content -Path (Join-Path $logDir ('sync-{0:yyyyMMdd}.log' -f (Get-Date))) -Value $line
}

function Get-ApiKey($Config) {
    if ($Config.ApiKeyProtected) {
        # DPAPI: only the Windows user who ran -SaveKey (on this PC) can decrypt it.
        $secure = ConvertTo-SecureString $Config.ApiKeyProtected
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    if ($Config.ApiKey) { return $Config.ApiKey }
    throw 'No API key configured. Run: sync-employees.bat -SaveKey'
}

function ConvertTo-JsonValue($Value) {
    if ($Value -is [DBNull]) { return $null }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-ddTHH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [guid]) { return $Value.ToString() }
    return $Value
}

function Compress-Gzip([byte[]]$Bytes) {
    $out = New-Object IO.MemoryStream
    $gzip = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionMode]::Compress)
    $gzip.Write($Bytes, 0, $Bytes.Length)
    $gzip.Close()
    return , $out.ToArray()
}

function Save-State($Known) {
    $tmp = "$statePath.tmp"
    $Known | ConvertTo-Json -Compress | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $statePath -Force
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    if ($SaveKey) {
        $secure = Read-Host 'Paste the API key for this branch' -AsSecureString
        $config | Add-Member -NotePropertyName ApiKeyProtected -NotePropertyValue (ConvertFrom-SecureString $secure) -Force
        $config | Add-Member -NotePropertyName ApiKey -NotePropertyValue '' -Force
        $config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-Host "API key saved (encrypted for $env:USERDOMAIN\$env:USERNAME)."
        exit 0
    }

    $baseUrl = $config.ApiUrl.TrimEnd('/')
    $batchSize = if ($config.BatchSize) { [int]$config.BatchSize } else { 1000 }

    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    $client.DefaultRequestHeaders.Add('X-Branch-Id', [string]$config.BranchGuid)
    $client.DefaultRequestHeaders.Add('X-Api-Key', (Get-ApiKey $config))

    if ($Test) {
        $resp = $client.GetAsync("$baseUrl/api/ping").GetAwaiter().GetResult()
        $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { throw "Ping failed: HTTP $([int]$resp.StatusCode) $body" }
        Write-Log "Ping OK: $body"
        exit 0
    }

    # 1. Read the branch table.
    $table = New-Object System.Data.DataTable
    $conn = New-Object System.Data.SqlClient.SqlConnection $config.ConnectionString
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'm_employee'"
        $branchColumns = @{}
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) { $branchColumns[$reader.GetString(0)] = $true }
        $reader.Close()
        if ($branchColumns.Count -eq 0) { throw 'Table dbo.m_employee not found in the branch database.' }

        $present = @($Columns | Where-Object { $branchColumns.ContainsKey($_) })
        $missing = @($Columns | Where-Object { -not $branchColumns.ContainsKey($_) })
        $missingRequired = @($missing | Where-Object { $RequiredColumns -contains $_ })
        if ($missingRequired.Count -gt 0) { throw "Branch m_employee is missing required column(s): $($missingRequired -join ', ')" }
        if ($missing.Count -gt 0) { Write-Log "Branch m_employee has no column(s) $($missing -join ', ') - sending them as null." }

        $cmd.CommandText = 'SELECT ' + (($present | ForEach-Object { "[$_]" }) -join ', ') + ' FROM dbo.m_employee'
        $cmd.CommandTimeout = 120
        $table.Load($cmd.ExecuteReader())
    }
    finally { $conn.Close() }

    # 2. Keep only rows whose content changed since the last successful sync.
    $known = @{}
    if (Test-Path $statePath) {
        (Get-Content $statePath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $known[$_.Name] = $_.Value }
    }

    $sha = [Security.Cryptography.SHA256]::Create()
    $pending = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $table.Rows) {
        $obj = [ordered]@{}
        $parts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($c in $Columns) {
            $v = if ($branchColumns.ContainsKey($c)) { ConvertTo-JsonValue $row[$c] } else { $null }
            $obj[$c] = $v
            $parts.Add([string]$v)
        }
        $id = [string]$obj.EmployeeID
        $hash = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($parts -join [char]31)))
        if ($Full -or $known[$id] -ne $hash) {
            $pending.Add([pscustomobject]@{ Id = $id; Hash = $hash; Row = $obj })
        }
    }

    Write-Log "Read $($table.Rows.Count) employees, $($pending.Count) to send$(if ($Full) { ' (full)' })."
    if ($pending.Count -eq 0) { exit 0 }

    # 3. Send in batches.
    $totals = @{ Inserted = 0; Updated = 0; Unchanged = 0 }
    for ($i = 0; $i -lt $pending.Count; $i += $batchSize) {
        $batch = $pending.GetRange($i, [Math]::Min($batchSize, $pending.Count - $i))
        $json = ConvertTo-Json -InputObject @($batch | ForEach-Object { $_.Row }) -Depth 3 -Compress

        $content = New-Object System.Net.Http.ByteArrayContent(, (Compress-Gzip ([Text.Encoding]::UTF8.GetBytes($json))))
        $content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue 'application/json'
        $content.Headers.ContentEncoding.Add('gzip')

        $resp = $client.PostAsync("$baseUrl/api/employees/upsert", $content).GetAwaiter().GetResult()
        $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { throw "Batch at row $i failed: HTTP $([int]$resp.StatusCode) $body" }

        $r = $body | ConvertFrom-Json
        $totals.Inserted += $r.inserted; $totals.Updated += $r.updated; $totals.Unchanged += $r.unchanged
        Write-Log "Batch $($i / $batchSize + 1): $($batch.Count) sent -> inserted $($r.inserted), updated $($r.updated), unchanged $($r.unchanged)"

        foreach ($p in $batch) { $known[$p.Id] = $p.Hash }
        Save-State $known
    }

    Write-Log "Done: inserted $($totals.Inserted), updated $($totals.Updated), unchanged $($totals.Unchanged)."
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
