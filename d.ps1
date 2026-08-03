# Fix sshd failing to start with error 1053 on Windows.
# Cause is nearly always host-key file permissions, or a bad sshd_config.

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host $m }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  STOP. Not an Administrator window.`n" -ForegroundColor Red
    return
}

Say "`n=== sshd repair on $env:COMPUTERNAME ===`n"

Stop-Service sshd -Force -ErrorAction SilentlyContinue

# --- 1. Host key permissions ---
Say "[1/4] Host key permissions"
Get-ChildItem 'C:\ProgramData\ssh\ssh_host_*_key' -ErrorAction SilentlyContinue | ForEach-Object {
    icacls.exe $_.FullName /inheritance:r /grant 'SYSTEM:F' /grant 'Administrators:F' | Out-Null
    Say "      locked down $($_.Name)"
}
# The ssh directory itself must not be world-writable either.
icacls.exe 'C:\ProgramData\ssh' /inheritance:r /grant 'SYSTEM:F' /grant 'Administrators:F' `
    /grant 'Authenticated Users:(RX)' /T /C | Out-Null

# --- 2. Validate sshd_config ---
Say "[2/4] Config check"
$sshd = 'C:\Windows\System32\OpenSSH\sshd.exe'
if (Test-Path $sshd) {
    $t = & $sshd -t 2>&1
    if ($t) { Say "      sshd_config complaints:"; $t | ForEach-Object { Say "        $_" } }
    else    { Say "      config OK" }
} else {
    Say "      sshd.exe MISSING - the capability did not really install"
}

# --- 3. Start ---
Say "[3/4] Starting"
sc.exe start sshd | Out-Null
Start-Sleep -Seconds 4
$s = (Get-Service sshd -ErrorAction SilentlyContinue).Status
Say "      sshd is now: $s"

# --- 4. If still down, show why ---
Say "[4/4] Result"
if ($s -eq 'Running') {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object { $_.IPAddress -like '192.168.*' }).IPAddress
    Say "`n  SUCCESS. sshd is running."
    Say "  Machine: $env:COMPUTERNAME   User: $env:USERNAME   LAN IP: $ip"
    Say "  Tell Claude it is up. Nothing else needed from you.`n"
} else {
    Say "`n  STILL DOWN. Most recent sshd errors:`n"
    Get-WinEvent -FilterHashtable @{ LogName='Application'; ProviderName='sshd' } `
        -MaxEvents 5 -ErrorAction SilentlyContinue |
        ForEach-Object { Say "  - $($_.TimeCreated.ToString('HH:mm:ss')): $($_.Message)" }

    Get-WinEvent -FilterHashtable @{ LogName='System' } -MaxEvents 200 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'sshd|OpenSSH' } | Select-Object -First 3 |
        ForEach-Object { Say "  - SYS $($_.TimeCreated.ToString('HH:mm:ss')): $($_.Message)" }

    $log = 'C:\ProgramData\ssh\logs\sshd.log'
    if (Test-Path $log) { Say "`n  sshd.log tail:"; Get-Content $log -Tail 15 | ForEach-Object { Say "    $_" } }
    Say ""
}
