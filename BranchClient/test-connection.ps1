<#
.SYNOPSIS
  Checks every link between this branch PC and the central biometricsAPI. Read-only: sends no data.

.DESCRIPTION
  Steps: config -> DNS -> TCP port -> API reachable -> API key (/api/ping)
         -> branch database -> columns of every table in tables.ps1.
  Each step prints [ OK ] or [FAIL] with the reason; later steps still run.
  Exit code = number of failed steps (0 = all good).

.EXAMPLE
  test-connection.bat
  test-connection.bat -ConfigPath D:\other\sync-config.json
#>
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'sync-config.json')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

# The tables and columns sync.ps1 sends.
. (Join-Path $PSScriptRoot 'tables.ps1')

$script:failures = 0

function Invoke-Step([string]$Name, [scriptblock]$Check) {
    try {
        $detail = & $Check
        Write-Host ('[ OK ] {0}' -f $Name) -ForegroundColor Green
        if ($detail) { $detail | ForEach-Object { Write-Host "       $_" } }
        return $true
    }
    catch {
        $script:failures++
        Write-Host ('[FAIL] {0}' -f $Name) -ForegroundColor Red
        $_.Exception.Message -split "`n" | ForEach-Object { Write-Host "       $_" -ForegroundColor Yellow }
        return $false
    }
}

function Get-ApiKey($Config) {
    if ($Config.ApiKeyProtected) {
        $secure = ConvertTo-SecureString $Config.ApiKeyProtected
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    return $Config.ApiKey
}

# Short description of an HTTP response, recognising Cloudflare's own error pages.
function Format-Response($Response, [string]$Body) {
    $lines = @("HTTP $([int]$Response.StatusCode) $($Response.ReasonPhrase)")
    if ($Response.Headers.Contains('cf-ray')) { $lines += 'Passed through Cloudflare.' }
    if ($Body -match '<html') {
        $lines += 'Body is an HTML page (probably Cloudflare or IIS, not the API).'
        if ($Body -match '<title>(.*?)</title>') { $lines += "Page title: $($Matches[1])" }
    }
    elseif ($Body) {
        $lines += 'Body: ' + ($(if ($Body.Length -gt 400) { $Body.Substring(0, 400) + '...' } else { $Body }))
    }
    return $lines
}

Write-Host ''
Write-Host "biometricsAPI connection test   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   $env:COMPUTERNAME"
Write-Host ('-' * 70)

# 1. Config ----------------------------------------------------------------
$config = $null; $uri = $null; $apiKey = $null
$configOk = Invoke-Step "Read config ($ConfigPath)" {
    if (-not (Test-Path $ConfigPath)) { throw "File not found." }
    $script:config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    if (-not $config.ApiUrl) { throw 'ApiUrl is empty.' }
    $script:uri = [Uri]$config.ApiUrl.TrimEnd('/')
    if ($uri.Scheme -notin 'http', 'https') { throw "ApiUrl must start with https:// (got '$($config.ApiUrl)')." }

    $g = [guid]::Empty
    if (-not [guid]::TryParse([string]$config.BranchGuid, [ref]$g)) { throw "BranchGuid '$($config.BranchGuid)' is not a valid GUID." }

    $source = if ($config.ApiKeyProtected) { "encrypted (-SaveKey, user $env:USERDOMAIN\$env:USERNAME)" } elseif ($config.ApiKey) { 'plain text in config' } else { 'MISSING' }
    try { $script:apiKey = Get-ApiKey $config }
    catch { throw "API key could not be decrypted. It was saved by a different Windows user or PC: run sync.bat -SaveKey again as $env:USERDOMAIN\$env:USERNAME." }
    if (-not $apiKey) { throw 'No API key. Run sync.bat -SaveKey.' }

    $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder $config.ConnectionString
    @(
        "ApiUrl:     $($config.ApiUrl)",
        "BranchGuid: $($config.BranchGuid)",
        "API key:    $source, $($apiKey.Length) characters (expected 43)",
        "Branch DB:  server '$($csb.DataSource)', database '$($csb.InitialCatalog)'"
    )
}

if ($configOk) {
    # 2. DNS -------------------------------------------------------------------
    $dnsOk = Invoke-Step "DNS lookup of $($uri.Host)" {
        $ips = [Net.Dns]::GetHostAddresses($uri.Host) | ForEach-Object { $_.IPAddressToString }
        "Resolves to: $($ips -join ', ')"
    }

    # 3. TCP -------------------------------------------------------------------
    $tcpOk = $dnsOk -and (Invoke-Step "TCP connect to $($uri.Host):$($uri.Port)" {
        $tcp = New-Object Net.Sockets.TcpClient
        try {
            $connect = $tcp.ConnectAsync($uri.Host, $uri.Port)
            $done = $false
            try { $done = $connect.Wait(5000) }
            catch { throw "$($_.Exception.InnerException.InnerException.Message) Nothing is listening there: server down, wrong port in ApiUrl, or a firewall." }
            if (-not $done) { throw 'Timed out after 5 s (firewall, wrong port, or server down).' }
        }
        finally { $tcp.Close() }
    })

    if ($tcpOk) {
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(30)
        $base = $config.ApiUrl.TrimEnd('/')

        # 4. API reachable (no key needed) -------------------------------------
        Invoke-Step "API reachable ($base/swagger/v1/swagger.json)" {
            $resp = $client.GetAsync("$base/swagger/v1/swagger.json").GetAwaiter().GetResult()
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $resp.IsSuccessStatusCode) {
                $hint = switch ([int]$resp.StatusCode) {
                    404 { 'Wrong ApiUrl (check the IIS sub-path), or Swagger is disabled on the server.' }
                    403 { 'Blocked - often Cloudflare bot protection. Allow /api/* and /swagger/* for this client.' }
                    { $_ -ge 500 } { 'Server error: check the API stdout log / Event Viewer on the server.' }
                    default { '' }
                }
                throw ((@(Format-Response $resp ($body.Substring(0, [Math]::Min(2000, $body.Length)))) + $hint) -join "`n")
            }
            "HTTP $([int]$resp.StatusCode) - the API is answering."
        } | Out-Null

        # 5. API key ------------------------------------------------------------
        Invoke-Step 'API key accepted (GET /api/ping)' {
            $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "$base/api/ping")
            $req.Headers.Add('X-Branch-Id', [string]$config.BranchGuid)
            $req.Headers.Add('X-Api-Key', $apiKey)
            $resp = $client.SendAsync($req).GetAwaiter().GetResult()
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $resp.IsSuccessStatusCode) {
                $hint = switch ([int]$resp.StatusCode) {
                    401 { 'The API rejected the key - the error above says why (wrong key / branch not registered).' }
                    429 { 'Rate limited - wait a minute and retry.' }
                    { $_ -ge 500 } { 'Server error while checking the key - usually the API cannot reach its own database (connection string / SQL login for the IIS app pool).' }
                    default { '' }
                }
                throw ((@(Format-Response $resp $body) + $hint) -join "`n")
            }
            $r = $body | ConvertFrom-Json
            "Branch: $($r.branchName) ($($r.branchGuid)), server time $($r.serverTime)"
        } | Out-Null
    }

    # 6. Branch database --------------------------------------------------------
    $dbOk = Invoke-Step 'Branch database connection' {
        $conn = New-Object System.Data.SqlClient.SqlConnection $config.ConnectionString
        $conn.Open()
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT @@SERVERNAME, DB_NAME(), SUSER_SNAME()"
            $r = $cmd.ExecuteReader(); $r.Read() | Out-Null
            $info = "Connected to $($r.GetString(0)) / $($r.GetString(1)) as $($r.GetString(2))"
            $r.Close()
            $info
        }
        finally { $conn.Close() }
    }

    # 7. Each synced table: exists, row count, columns ----------------------------
    if ($dbOk) {
        foreach ($def in $SyncTables) {
            Invoke-Step "dbo.$($def.Name) has the columns the sync needs" {
                $conn = New-Object System.Data.SqlClient.SqlConnection $config.ConnectionString
                $conn.Open()
                try {
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = @t"
                    $cmd.Parameters.AddWithValue('@t', $def.Name) | Out-Null
                    $have = @{}
                    $r = $cmd.ExecuteReader()
                    while ($r.Read()) { $have[$r.GetString(0)] = $true }
                    $r.Close()
                    if ($have.Count -eq 0) { throw "Table dbo.$($def.Name) does not exist in this database." }

                    $cmd.Parameters.Clear()
                    $cmd.CommandText = "SELECT COUNT(*) FROM dbo.[$($def.Name)]"
                    $rows = [int]$cmd.ExecuteScalar()
                }
                finally { $conn.Close() }

                $missing = @($def.Columns | Where-Object { -not $have.ContainsKey($_) })
                $missingRequired = @($missing | Where-Object { $def.Required -contains $_ })
                if ($missingRequired.Count -gt 0) { throw "Missing required column(s): $($missingRequired -join ', ')" }
                $count = $def.Columns.Count
                if ($missing.Count -gt 0) { "$rows rows. $($count - $missing.Count) of $count columns present. Optional, not in this table (sent as null): $($missing -join ', ')" }
                else { "$rows rows. All $count columns present." }
            } | Out-Null
        }
    }
}

Write-Host ('-' * 70)
if ($script:failures -eq 0) {
    Write-Host 'All checks passed. sync.bat should work.' -ForegroundColor Green
}
else {
    Write-Host "$script:failures check(s) failed - see [FAIL] lines above." -ForegroundColor Red
}
exit $script:failures
