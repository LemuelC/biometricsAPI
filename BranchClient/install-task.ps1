<#
.SYNOPSIS
  Creates (or replaces) the Windows scheduled task that runs the biometrics sync.

.DESCRIPTION
  Default schedule: days 1, 2, 16 and 17 of every month at 01:00, running
      sync.ps1 -PayrollPeriod
  which sends the last completed payroll half:
      run on the 1st / 2nd   -> previous month 16..end
      run on the 16th / 17th -> this month 1..15
  m_employee is always sent in full.

  If the PC is off at the scheduled time, the task runs as soon as it is back on.
  The task runs as the Windows user who installs it. That must be the same user that ran
  "sync.bat -SaveKey" (the saved API key can only be decrypted by that user), and that user
  needs access to the branch database.

.EXAMPLE
  install-task.bat                              days 1,2,16,17 at 01:00, runs even when logged off (asks for your Windows password)
  install-task.bat -Time 02:30                  another time of day
  install-task.bat -Daily                       every day instead (sends the last DefaultDays days, changed rows only)
  install-task.bat -OnlyWhenLoggedOn            no password needed, but only runs while you are logged on
  install-task.bat -Remove                      delete the task
#>
param(
    [string]$Time = '01:00',
    [switch]$Daily,
    [switch]$OnlyWhenLoggedOn,
    [switch]$Remove,
    [string]$TaskName = 'Biometrics Sync'
)

$ErrorActionPreference = 'Stop'

try {
    if ($Remove) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Task '$TaskName' removed."
        exit 0
    }

    $syncScript = Join-Path $PSScriptRoot 'sync.ps1'
    $configPath = Join-Path $PSScriptRoot 'sync-config.json'
    if (-not (Test-Path $syncScript)) { throw "sync.ps1 not found next to this script ($PSScriptRoot)." }

    $at = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Time, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$at)) {
        throw "-Time must be HH:mm (24-hour), e.g. 01:00 or 14:30. Got '$Time'."
    }

    # The saved API key is DPAPI-encrypted for one Windows user: make sure it is this one.
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($config.ApiKeyProtected) {
        try { ConvertTo-SecureString $config.ApiKeyProtected | Out-Null }
        catch { throw "The API key in sync-config.json was saved by a different Windows user, so the task could not read it when running as $user. Run 'sync.bat -SaveKey' as $user first, then install the task again." }
    } elseif (-not $config.ApiKey) {
        throw "No API key in sync-config.json. Run 'sync.bat -SaveKey' first."
    }

    $start = (Get-Date).Date.Add($at.TimeOfDay).ToString('yyyy-MM-ddTHH:mm:ss')
    if ($Daily) {
        $syncArgs = ''
        $trigger = "<CalendarTrigger><StartBoundary>$start</StartBoundary><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>"
        $what = "every day at $Time (last DefaultDays days, changed rows only)"
    } else {
        $syncArgs = ' -PayrollPeriod'
        $months = (1..12 | ForEach-Object { '<{0}/>' -f [Globalization.CultureInfo]::InvariantCulture.DateTimeFormat.GetMonthName($_) }) -join ''
        $trigger = "<CalendarTrigger><StartBoundary>$start</StartBoundary><ScheduleByMonth>" +
            "<DaysOfMonth><Day>1</Day><Day>2</Day><Day>16</Day><Day>17</Day></DaysOfMonth>" +
            "<Months>$months</Months></ScheduleByMonth></CalendarTrigger>"
        $what = "days 1, 2, 16 and 17 of every month at $Time (last completed payroll period)"
    }

    $logonType = if ($OnlyWhenLoggedOn) { 'InteractiveToken' } else { 'Password' }
    $esc = { param($s) [Security.SecurityElement]::Escape($s) }

    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Sends this branch's biometrics data to the central biometricsAPI (sync.ps1$syncArgs). Logs: $(& $esc (Join-Path $PSScriptRoot 'logs'))</Description>
  </RegistrationInfo>
  <Triggers>$trigger</Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$(& $esc $user)</UserId>
      <LogonType>$logonType</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$(& $esc "-NoProfile -ExecutionPolicy Bypass -File `"$syncScript`"$syncArgs")</Arguments>
      <WorkingDirectory>$(& $esc $PSScriptRoot)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

    if ($OnlyWhenLoggedOn) {
        Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
    } else {
        Write-Host "The task runs as $user even when nobody is logged on, so Windows needs that account's password."
        $cred = Get-Credential -UserName $user -Message "Windows password for $user (stored by Task Scheduler, not by this script)"
        if (-not $cred) { throw 'Cancelled.' }
        Register-ScheduledTask -TaskName $TaskName -Xml $xml -User $user -Password $cred.GetNetworkCredential().Password -Force | Out-Null
    }

    $info = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
    Write-Host ''
    Write-Host "Task '$TaskName' installed: $what, as $user."
    Write-Host "Next run: $($info.NextRunTime)"
    Write-Host "Run it now to test:  schtasks /Run /TN `"$TaskName`"   (then check the logs folder)"
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
