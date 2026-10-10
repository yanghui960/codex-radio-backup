# ============================================================
#  backup-codex-radio.ps1
#  One-click backup of the FCC Codex Radio workflow
#  (EasyInput V2 board + Windows Host + DashScope + Codex)
#  Usage:  powershell -ExecutionPolicy Bypass -File backup-codex-radio.ps1
#  Output: C:\Users\Administrator\codex-radio-backup\<timestamp>\
# ============================================================
$ErrorActionPreference = "Stop"

$Root      = "C:\Users\Administrator\Doubao\chats\2026-10-05\new-chat\codex_keyboard"
$DataA     = "C:\Users\Administrator\Library\Application Support\EasyCodexInput"
$DataB     = "C:\Users\Administrator\Library\Application Support\easy-codex-host"
$Sessions  = "C:\Users\Administrator\.codex\sessions"
$BackupBase= "C:\Users\Administrator\codex-radio-backup"

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Dest  = Join-Path $BackupBase $Stamp
New-Item -ItemType Directory -Path $Dest -Force | Out-Null
Write-Host "[1/7] Backup target: $Dest"

# ---- 1. Host binary / scripts / logs ----
Write-Host "[2/7] Copying Host binary & scripts..."
Copy-Item (Join-Path $Root "target\debug\easy-codex-host.exe") $Dest -Force
Copy-Item (Join-Path $Root "target\debug\start-host.bat")      $Dest -Force
Copy-Item (Join-Path $Root "target\debug\watchdog.ps1")        $Dest -Force
Copy-Item (Join-Path $Root "target\debug\host-daemon.log")     $Dest -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root "target\debug\host-daemon-err.log") $Dest -Force -ErrorAction SilentlyContinue

# ---- 2. Firmware: bin + main source + build config ----
Write-Host "[3/7] Copying firmware (bin + main + config)..."
New-Item -ItemType Directory -Path (Join-Path $Dest "firmware\main") -Force | Out-Null
Copy-Item (Join-Path $Root "firmware\build\easy_codex_input.bin") (Join-Path $Dest "firmware") -Force
Copy-Item (Join-Path $Root "build-firmware.ps1")                  (Join-Path $Dest "firmware") -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root "firmware\main\*")                     (Join-Path $Dest "firmware\main") -Recurse -Force
foreach ($f in @("CMakeLists.txt","sdkconfig.defaults","partitions.csv","dependencies.lock","README.md","UPSTREAM.md")) {
  $src = Join-Path $Root "firmware\$f"
  if (Test-Path $src) { Copy-Item $src (Join-Path $Dest "firmware") -Force }
}

# ---- 3. Host source (all Windows fixes) ----
Write-Host "[4/7] Copying Host source..."
New-Item -ItemType Directory -Path (Join-Path $Dest "src") -Force | Out-Null
Copy-Item (Join-Path $Root "app\host\src\*") (Join-Path $Dest "src") -Recurse -Force
Copy-Item (Join-Path $Root "app\host\Cargo.toml") $Dest -Force
Copy-Item (Join-Path $Root "Cargo.toml") $Dest -Force -ErrorAction SilentlyContinue
if (Test-Path (Join-Path $Root ".cargo")) {
  Copy-Item (Join-Path $Root ".cargo") (Join-Path $Dest "cargo-config") -Recurse -Force
}

# ---- 4. Data dirs (DB / device secret / playback cache / .env) ----
Write-Host "[5/7] Copying data dirs..."
if (Test-Path $DataA) { Copy-Item $DataA $Dest -Recurse -Force }
if (Test-Path $DataB) { Copy-Item $DataB $Dest -Recurse -Force }

# ---- 5. Codex sessions ----
if (Test-Path $Sessions) { Copy-Item $Sessions (Join-Path $Dest "codex-sessions") -Recurse -Force }

# ---- 6. Config export (env / registry / network / board / doc) ----
Write-Host "[6/7] Exporting config..."
$cfg = @{}
$cfg["DASHSCOPE_API_KEY"] = [Environment]::GetEnvironmentVariable("DASHSCOPE_API_KEY", "User")
$cfg["EASY_CODEX_CLI"]    = [Environment]::GetEnvironmentVariable("EASY_CODEX_CLI", "User")
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$cfg["RegRun"] = @{
  "EasyCodexHost"     = (Get-ItemProperty $runKey -Name "EasyCodexHost" -ErrorAction SilentlyContinue).EasyCodexHost
  "EasyCodexWatchdog" = (Get-ItemProperty $runKey -Name "EasyCodexWatchdog" -ErrorAction SilentlyContinue).EasyCodexWatchdog
}

# Detect live network config instead of hardcoding
$net = @{}
$adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($adapter) {
  $net["AdapterDescription"] = $adapter.InterfaceDescription
  $net["AdapterName"]        = $adapter.Name
}
$ipcfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
if ($ipcfg) {
  $net["StaticIP"]  = $ipcfg.IPv4Address[0].IPAddress
  $net["Mask"]      = $ipcfg.IPv4Address[0].PrefixLength
  $net["Gateway"]   = $ipcfg.IPv4DefaultGateway[0].NextHop
  $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses -and $_.InterfaceIndex -eq $ipcfg.InterfaceIndex } | Select-Object -First 1).ServerAddresses -join ","
  $net["DNS"] = $dns
}
if (-not $net.ContainsKey("StaticIP")) { $net["StaticIP"] = "192.168.3.100" } # fallback to known good
$cfg["Network"] = $net
$cfg["Board"]   = @{ IP="192.168.3.101"; MAC="c4-9e-7e-07-4d-a8"; UDPPort=17333; WifiSSID="TP-LINK_C3B6"; WifiPass="12345678" }
$cfg["Host"]    = @{ Exe=(Join-Path $Root "target\debug\easy-codex-host.exe"); UDPPort=17333 }
$cfg["DocUrl"]  = "https://my.feishu.cn/docx/GJjSdfKOdoRcIKxPppocVAiYndd"
$cfg["Codex"]   = @{ SessionSlot1="01a10a93-0223-78c0-b2a9-9297ff75d173" }
$cfg | ConvertTo-Json -Depth 6 | Out-File (Join-Path $Dest "config.json") -Encoding utf8

# ---- 7. README ----
Write-Host "[7/7] Writing README..."
$readme = @"
FCC Codex Radio - Full Backup Snapshot
=====================================
Backup time : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Feishu doc  : https://my.feishu.cn/docx/GJjSdfKOdoRcIKxPppocVAiYndd

CONTENTS
--------
easy-codex-host.exe     Host daemon (all Windows fixes)
start-host.bat          Hidden autostart launcher
watchdog.ps1            30s watchdog
host-daemon*.log        Runtime logs
firmware\               easy_codex_input.bin + main source + build config
src\                    Host Rust source (all fixes) + Cargo.toml + cargo-config
EasyCodexInput\         state.sqlite3 / device-secret.hex / run\playback cache
easy-codex-host\        data dir (.env if present)
codex-sessions\         Codex rollout sessions (slot1 bound)
config.json             Env vars / registry / network / board / doc link

RESTORE
-------
powershell -ExecutionPolicy Bypass -File restore-codex-radio.ps1 -BackupPath "THIS FOLDER"
(or run restore-codex-radio.ps1 with no args to use the latest backup)

NOTE
----
config.json contains the DashScope API key in plain text. Keep this
folder private - do NOT share or upload it.
"@
$readme | Out-File (Join-Path $Dest "README.txt") -Encoding utf8

Write-Host ""
Write-Host "BACKUP COMPLETE: $Dest"
$size = (Get-ChildItem $Dest -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("Total size: {0:N1} MB" -f ($size/1MB))
