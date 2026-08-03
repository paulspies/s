# sshd starts but times out after 30s. Find out why.
# Prints a short report. Nothing here changes the system except a final start attempt.

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host $m }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n  STOP. Not an Administrator window.`n" -ForegroundColor Red
    return
}

Say "`n=== sshd DIAGNOSIS on $env:COMPUTERNAME ===`n"

# --- 1. What does the service actually point at, and who runs it? ---
Say "[1] Service registration"
$qc = sc.exe qc sshd
$qc | Where-Object { $_ -match 'BINARY_PATH_NAME|SERVICE_START_NAME|START_TYPE' } |
    ForEach-Object { Say "    $($_.Trim())" }

# --- 2. Competing OpenSSH copies. This is the usual cause. ---
Say "`n[2] Every sshd.exe on this machine"
$found = @()
foreach ($root in 'C:\Windows\System32\OpenSSH','C:\Program Files\OpenSSH',
                  'C:\Program Files\Git\usr\bin','C:\Program Files (x86)\OpenSSH',
                  'C:\ProgramData\chocolatey\bin') {
    $p = Join-Path $root 'sshd.exe'
    if (Test-Path $p) {
        $v = (Get-Item $p).VersionInfo.ProductVersion
        Say "    FOUND $p  (version $v)"
        $found += $p
    }
}
if ($found.Count -eq 0) { Say "    none in the usual places" }
if ($found.Count -gt 1) { Say "    >>> MORE THAN ONE. This is very likely the cause. <<<" }

Say "`n    PATH order for ssh:"
(Get-Command ssh.exe -All -ErrorAction SilentlyContinue) |
    ForEach-Object { Say "      $($_.Source)" }

# --- 3. Run sshd in the foreground and watch it fail ---
Say "`n[3] Foreground run, 12 second window (this is the real error)"
$exe = 'C:\Windows\System32\OpenSSH\sshd.exe'
if (Test-Path $exe) {
    $out = Join-Path $env:TEMP 'sshd_dbg.txt'
    Remove-Item $out -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $exe -ArgumentList '-ddd' -NoNewWindow -PassThru `
            -RedirectStandardError $out -RedirectStandardOutput "$out.o"
    Start-Sleep -Seconds 12
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    foreach ($f in @($out, "$out.o")) {
        if ((Test-Path $f) -and (Get-Item $f).Length -gt 0) {
            Get-Content $f -Tail 25 | ForEach-Object { Say "    $_" }
        }
    }
} else { Say "    sshd.exe missing from System32\OpenSSH" }

# --- 4. Antivirus, which can silently hold the process ---
Say "`n[4] Security products"
Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
    ForEach-Object { Say "    $($_.displayName)" }

Say "`n=== END. Screenshot this and send it. ===`n"
