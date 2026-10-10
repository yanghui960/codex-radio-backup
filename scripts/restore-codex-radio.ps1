# ============================================================
#  restore-codex-radio.ps1
#  One-click restore of the FCC Codex Radio workflow
#  Usage:  powershell -ExecutionPolicy Bypass -File restore-codex-radio.ps1
#          (no args = latest backup; or -BackupPath "C:\...\backup-folder")
#  Steps:  stop old daemon -> restore files -> restore env/registry/static IP
#          -> restart daemon
#  NOTE:   If the board firmware was overwritten, re-flash it manually
#          (hold BOOT key while plugging USB).
# ============================================================
param([string]$BackupPath = "")

$ErrorActionPreference = "Stop"

# ---- 0. Locate backup ----
if (-not $BackupPath) {
  $latest = Get-ChildItem "C:\Users\Administrator\codex-radio-backup" -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
  if (-not $latest) { Write-Host "[X] No backup found under C:\Users\Administrator\codex-radio-backup"; exit 1 }
  $BackupPath = $latest.FullName
}
if (-not (Test-Path $BackupPath)) { Write-Host "[X] Backup path not found: $BackupPath"; exit 1 }
Write-Host "[OK] Restoring from: $BackupPath"

$Root = "C:\Users\Administrator\Doubao\chats\2026-10-05\new-chat\codex_keyboard"

# ---- 1. Stop old daemon / watchdog ----
Write-Host "[1/7] Stopping old daemon & watchdog..."
Get-Process easy-codex-host -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match "watchdog" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2

# ---- 2. Restore Host binary / scripts / logs ----
Write-Host "[2/7] Restoring Host binary & scripts..."
New-Item -ItemType Directory -Path (Join-Path $Root "target\debug") -Force | Out-Null
Copy-Item (Join-Path $BackupPath "easy-codex-host.exe") (Join-Path $Root "target\debug") -Force
Copy-Item (Join-Path $BackupPath "start-host.bat")      (Join-Path $Root "target\debug") -Force
Copy-Item (Join-Path $BackupPath "watchdog.ps1")        (Join-Path $Root "target\debug") -Force
foreach ($f in @("host-daemon.log","host-daemon-err.log")) {
  $s = Join-Path $BackupPath $f
  if (Test-Path $s) { Copy-Item $s (Join-Path $Root "target\debug") -Force }
}

# ---- 3. Restore firmware ----
Write-Host "[3/7] Restoring firmware..."
New-Item -ItemType Directory -Path (Join-Path $Root "firmware\main") -Force | Out-Null
if (Test-Path (Join-Path $BackupPath "firmware\easy_codex_input.bin")) {
  New-Item -ItemType Directory -Path (Join-Path $Root "firmware\build") -Force | Out-Null
  Copy-Item (Join-Path $BackupPath "firmware\easy_codex_input.bin") (Join-Path $Root "firmware\build") -Force
}
if (Test-Path (Join-Path $BackupPath "firmware\main")) {
  Copy-Item (Join-Path $BackupPath "firmware\main\*") (Join-Path $Root "firmware\main") -Recurse -Force
}
foreach ($f in @("CMakeLists.txt","sdkconfig.defaults","partitions.csv","dependencies.lock","README.md","UPSTREAM.md","build-firmware.ps1")) {
  $s = Join-Path $BackupPath "firmware\$f"
  if (Test-Path $s) { Copy-Item $s (Join-Path $Root "firmware") -Force -ErrorAction SilentlyContinue }
}

# ---- 4. Restore Host source ----
Write-Host "[4/7] Restoring Host source..."
if (Test-Path (Join-Path $BackupPath "src")) {
  New-Item -ItemType Directory -Path (Join-Path $Root "app\host\src") -Force | Out-Null
  Copy-Item (Join-Path $BackupPath "src\*") (Join-Path $Root "app\host\src") -Recurse -Force
}
foreach ($f in @("Cargo.toml")) {
  $s = Join-Path $BackupPath $f
  if (Test-Path $s) { Copy-Item $s (Join-Path $Root "app\host") -Force }
}
if (Test-Path (Join-Path $BackupPath "cargo-config")) {
  New-Item -ItemType Directory -Path (Join-Path $Root ".cargo") -Force | Out-Null
  Copy-Item (Join-Path $BackupPath "cargo-config\*") (Join-Path $Root ".cargo") -Recurse -Force
}

# ---- 5. Restore data dirs ----
Write-Host "[5/7] Restoring data dirs..."
$DataA = "C:\Users\Administrator\Library\Application Support\EasyCodexInput"
$DataB = "C:\Users\Administrator\Library\Application Support\easy-codex-host"
if (Test-Path (Join-Path $BackupPath "EasyCodexInput")) {
  New-Item -ItemType Directory -Path $DataA -Force | Out-Null
  Copy-Item (Join-Path $BackupPath "EasyCodexInput\*") $DataA -Recurse -Force
}
if (Test-Path (Join-Path $BackupPath "easy-codex-host")) {
  New-Item -ItemType Directory -Path $DataB -Force | Out-Null
  Copy-Item (Join-Path $BackupPath "easy-codex-host\*") $DataB -Recurse -Force
}

# ---- 6. Restore env vars / registry / static IP ----
Write-Host "[6/7] Restoring env vars, registry, static IP..."
$cfgFile = Join-Path $BackupPath "config.json"
if (Test-Path $cfgFile) {
  $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json

  if ($cfg.DASHSCOPE_API_KEY) {
    [Environment]::SetEnvironmentVariable("DASHSCOPE_API_KEY", $cfg.DASHSCOPE_API_KEY, "User")
    Write-Host "  DASHSCOPE_API_KEY restored"
  }
  if ($cfg.EASY_CODEX_CLI) {
    [Environment]::SetEnvironmentVariable("EASY_CODEX_CLI", $cfg.EASY_CODEX_CLI, "User")
    Write-Host "  EASY_CODEX_CLI restored"
  }
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  if ($cfg.RegRun.EasyCodexHost)     { Set-ItemProperty $runKey -Name "EasyCodexHost"     -Value $cfg.RegRun.EasyCodexHost     -Type String }
  if ($cfg.RegRun.EasyCodexWatchdog) { Set-ItemProperty $runKey -Name "EasyCodexWatchdog" -Value $cfg.RegRun.EasyCodexWatchdog -Type String }
  Write-Host "  Registry Run keys restored"

  if ($cfg.Network -and $cfg.Network.StaticIP) {
    $desc = $cfg.Network.AdapterDescription
    $name = $null
    if ($desc) {
      $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -eq $desc } | Select-Object -First 1
      if ($adapter) { $name = $adapter.Name }
    }
    if (-not $name) { $name = $cfg.Network.AdapterName }
    if (-not $name) {
      $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
      if ($adapter) { $name = $adapter.Name }
    }
    if ($name) {
      $ip   = $cfg.Network.StaticIP
      $mask = $cfg.Network.Mask
      $gw   = $cfg.Network.Gateway
      $dns  = $cfg.Network.DNS
      if ($mask -match "^\d+$") { $mask = "255.255.255.0" } # prefix length fallback
      Write-Host "  Setting static IP $ip on '$name'"
      netsh interface ip set address name="$name" static $ip $mask $gw 2>&1 | Out-Null
      if ($dns) { netsh interface ip set dns name="$name" static $dns 2>&1 | Out-Null }
      Start-Sleep -Seconds 3
    } else {
      Write-Host "  [WARN] No active adapter found, skipping static IP"
    }
  }
} else {
  Write-Host "  [WARN] config.json not found, skipping env/registry/network restore"
}

# ---- 7. Restart daemon (hidden) + watchdog ----
Write-Host "[7/7] Starting daemon & watchdog..."
$startBat = Join-Path $Root "target\debug\start-host.bat"
if (Test-Path $startBat) {
  Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startBat`"" -WindowStyle Hidden
}
$watchBat = Join-Path $Root "target\debug\watchdog.ps1"
if (Test-Path $watchBat) {
  Start-Process powershell -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchBat`"" -WindowStyle Hidden
}
Start-Sleep -Seconds 4

# ---- Verification ----
Write-Host ""
Write-Host "=== VERIFICATION ==="
$proc = Get-Process easy-codex-host -ErrorAction SilentlyContinue
if ($proc) { Write-Host "[OK] daemon running, PID: $($proc.Id -join ',')" } else { Write-Host "[FAIL] daemon NOT running" }
$netstat = netstat -an | Select-String ":17333" | Select-Object -First 2
if ($netstat) { Write-Host "[OK] UDP 17333 listening"; $netstat } else { Write-Host "[WARN] UDP 17333 not seen (may need a moment)" }
Write-Host ""
Write-Host "RESTORE COMPLETE."
Write-Host ""
Write-Host "NOTE: If the board firmware was overwritten, re-flash it:"
Write-Host "  1) Hold BOOT key, plug USB, release after COM3 appears"
Write-Host "  2) cd C:\Users\Administrator\Doubao\chats\2026-10-05\new-chat\codex_keyboard\firmware"
Write-Host "  3) idf.py -p COM3 flash   (after: unplug & replug USB)"
