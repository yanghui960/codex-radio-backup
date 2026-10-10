# codex-radio-backup

One-click backup & restore for the **FCC Codex Radio** workflow
(EasyInput V2 board + Windows Host daemon + DashScope ASR/TTS + Codex executor).

## What it does

- **Backup** (`backup-codex-radio.ps1`): snapshots the whole working state into
  `C:\Users\Administrator\codex-radio-backup\<timestamp>\`:
  - Host daemon binary + autostart/watchdog scripts + logs
  - Firmware bin + `main` source + build config
  - Host Rust source (all Windows fixes)
  - Data dirs (`state.sqlite3`, device secret, playback cache)
  - Codex sessions (slot-1 bound rollout)
  - `config.json` with env vars / registry keys / static IP / board info
- **Restore** (`restore-codex-radio.ps1`): restores the latest (or a given)
  backup — files, user env vars, registry Run keys, static IP (192.168.3.100),
  then restarts the hidden daemon + watchdog.

## Usage

```powershell
# backup
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup-codex-radio.ps1

# restore latest
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\restore-codex-radio.ps1

# restore a specific snapshot
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\restore-codex-radio.ps1 -BackupPath "C:\Users\Administrator\codex-radio-backup\20261010-130854"
```

## SECURITY

- The backup snapshot **contains the DashScope API key in plain text**
  (`config.json`). Keep backup folders private — never upload them.
- The scripts themselves read the key from the user environment variable
  `DASHSCOPE_API_KEY`; no secret is stored in this repository.
- Restore re-applies a static IP via `netsh`, which briefly drops the network.

## Notes

- If the board firmware gets overwritten (e.g. by another course task),
  re-flash: hold BOOT, plug USB (COM3 appears), then
  `idf.py -p COM3 flash` in the firmware dir.
- See `SKILL.md` for the full agent-facing usage guide.
