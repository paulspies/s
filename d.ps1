# Data-Center remote access setup. Run in an ELEVATED PowerShell.
# Installs OpenSSH Server + Tailscale, authorises Paul's PC2 to connect.
# Nothing here is destructive: every step checks before it acts.

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host $m }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  STOP. This window is not elevated." -ForegroundColor Red
    Write-Host "  Close it, right-click PowerShell, Run as administrator, then run this again.`n"
    return
}

Say "`n=== Data-Center setup: $env:COMPUTERNAME as $env:USERNAME ===`n"

# --- 1. OpenSSH Server ---
Say "[1/5] OpenSSH Server"
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null; Say "      installed" }
else { Say "      already installed" }

# --- 2. Services ---
Say "[2/5] Services"
foreach ($svc in 'sshd','ssh-agent') {
    Set-Service -Name $svc -StartupType Automatic
    Start-Service -Name $svc
    Say "      $svc -> $((Get-Service $svc).Status)"
}

# --- 3. Firewall ---
Say "[3/5] Firewall port 22"
if (-not (Get-NetFirewallRule -Name 'sshd-claude' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'sshd-claude' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    Say "      rule created"
} else { Say "      rule already present" }

New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null

# --- 4. Authorise PC2's key ---
# Windows quirk: for accounts in the Administrators group sshd reads
# administrators_authorized_keys, NOT the user's ~/.ssh/authorized_keys.
Say "[4/5] Authorising Paul's PC2 key"
$pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINp1BboF98uJXCwLOIexqspee1vWzMidWDFu8sTp6ufz pc2-to-datacenter'
$isAdmin = (Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*\$env:USERNAME" }) -ne $null

if ($isAdmin) {
    $akf = 'C:\ProgramData\ssh\administrators_authorized_keys'
    if (-not (Test-Path $akf)) { New-Item -ItemType File -Path $akf -Force | Out-Null }
    if ((Get-Content $akf -Raw -ErrorAction SilentlyContinue) -notmatch [regex]::Escape($pub)) {
        Add-Content -Path $akf -Value $pub -Encoding ascii
    }
    icacls.exe $akf /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
    Say "      -> $akf (admin account)"
} else {
    $dir = Join-Path $env:USERPROFILE '.ssh'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $akf = Join-Path $dir 'authorized_keys'
    if (-not (Test-Path $akf)) { New-Item -ItemType File -Path $akf | Out-Null }
    if ((Get-Content $akf -Raw -ErrorAction SilentlyContinue) -notmatch [regex]::Escape($pub)) {
        Add-Content -Path $akf -Value $pub -Encoding ascii
    }
    Say "      -> $akf (standard account)"
}

# --- 5. Tailscale ---
Say "[5/5] Tailscale"
$ts = 'C:\Program Files\Tailscale\tailscale.exe'
if (-not (Test-Path $ts)) {
    winget install --id Tailscale.Tailscale --silent `
        --accept-package-agreements --accept-source-agreements | Out-Null
}
if (Test-Path $ts) {
    Say "      installed. Bringing it up - SIGN IN AS filamfilms@gmail.com when the browser opens."
    & $ts up --unattended
    Start-Sleep -Seconds 3
    Say "`n      Tailscale IP: $(& $ts ip -4)"
} else {
    Say "      winget failed. Download manually: https://tailscale.com/download/windows"
}

Say "`n=== DONE ==="
Say "Username for Paul to use: $env:USERNAME"
Say "LAN IP: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' }).IPAddress)"
Say "Tell Claude the Tailscale IP above and this username.`n"
