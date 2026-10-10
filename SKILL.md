---
name: codex-radio-backup
description: 一键备份/一键回档「FCC 版 Codex 电台」工作流（EasyInput V2 硬件板 + Windows Host daemon + DashScope ASR/TTS + Codex 执行器）。当用户要求备份当前工作流、回档/恢复到 Codex 电台状态、切换第八课之前先备份、一键备份、一键回档、保存/还原这套系统配置，或提到 codex-radio-backup 时使用。备份覆盖 Host 程序与源码、固件 bin 与 main 源码、数据目录（state.sqlite3/设备密钥/播放缓存）、环境变量、注册表自启、静态 IP、Codex 会话；回档自动还原以上全部并重启 daemon。
---

# FCC Codex 电台 — 一键备份 / 一键回档

## 概述

本 Skill 封装了 FCC 版 Codex 任务电台工作流的完整快照与恢复能力，用于在用户改动系统（例如做第八课、改固件、改 Host）前后保存/还原当前可用的全链路状态（板子语音 → DashScope ASR → Codex 执行 → 语音播报）。

## 关键路径（只读参考，勿改）

- 项目根：`C:\Users\Administrator\Doubao\chats\2026-10-05\new-chat\codex_keyboard`
- Host 产物：`target\debug\easy-codex-host.exe`（daemon，隐藏运行）
- 自启脚本：`target\debug\start-host.bat`；守护：`target\debug\watchdog.ps1`（每 30s 保活）
- 真实状态库：`C:\Users\Administrator\Library\Application Support\EasyCodexInput\state.sqlite3`
- 播放缓存：`...\EasyCodexInput\run\last-playback.eiad` + `last-playback.meta.json`
- daemon 日志：`target\debug\host-daemon.log` / `host-daemon-err.log`
- 备份根目录：`C:\Users\Administrator\codex-radio-backup\<时间戳>\`

## 使用流程

### 1. 一键备份（改动系统前调用）

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill目录>\scripts\backup-codex-radio.ps1"
```

- 每次生成一个带时间戳的新备份目录（保留历史，不覆盖旧备份）
- 输出 `BACKUP COMPLETE: C:\Users\Administrator\codex-radio-backup\<时间戳>`

备份内容：
| 类别 | 内容 |
|---|---|
| Host | easy-codex-host.exe、start-host.bat、watchdog.ps1、运行日志 |
| 固件 | easy_codex_input.bin（已含 speaker）、main 源码、CMakeLists/sdkconfig.defaults/partitions.csv、build-firmware.ps1 |
| Host 源码 | app\host\src 全部（含 Windows 修复）、Cargo.toml、.cargo 配置 |
| 数据 | EasyCodexInput 目录（state.sqlite3/device-secret.hex/run 缓存）、easy-codex-host 目录（.env 如有） |
| 会话 | C:\Users\Administrator\.codex\sessions（slot1 绑定会话 rollout） |
| 配置 | config.json：DASHSCOPE_API_KEY、EASY_CODEX_CLI、注册表 Run 键、静态 IP/网关/DNS、板子信息（IP/MAC/Wi-Fi/端口）、作业文档链接 |

### 2. 一键回档（恢复最新备份）

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill目录>\scripts\restore-codex-radio.ps1"
```

指定历史备份：

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<本Skill目录>\scripts\restore-codex-radio.ps1" -BackupPath "C:\Users\Administrator\codex-radio-backup\<时间戳>"
```

回档自动完成：
1. 停止旧 daemon 与 watchdog
2. 还原 Host 程序/脚本/固件/源码/数据目录
3. 恢复用户级环境变量（DASHSCOPE_API_KEY、EASY_CODEX_CLI）与注册表 Run 键
4. 用 netsh 恢复静态 IP 192.168.3.100（网关 192.168.3.1、DNS 192.168.51.1）
5. 隐藏模式重启 daemon + watchdog
6. 输出验证结果（daemon 进程 + UDP 17333 监听）

## 注意事项（必须遵守）

1. **config.json 含 DASHSCOPE_API_KEY 明文**——备份目录属私密文件，不得外传、不得上传网盘/仓库。
2. **回档设置静态 IP 会使电脑断网数秒**（netsh 重新协商），属正常现象，勿中断脚本。
3. **板子固件若被第八课覆盖**：回档后需重新烧录——按住 BOOT 键插 USB 出现 COM3 → `cd firmware; idf.py -p COM3 flash` → 烧完拔插 USB 恢复。
4. **若之后需重新编译 Host**：必须先杀 daemon 进程再 `cargo build`（否则 LNK1105 文件占用报错）；crates.io 直连被死代理挡，需走 rsproxy 稀疏镜像（见项目 .cargo\config.toml）。
5. 电脑静态 IP 是板子里写死的目标地址（192.168.3.100:17333）；若电脑 IP 漂移（DHCP 重启后变化），板子语音发不到 Host，需用 netsh 重新固定静态 IP。
6. DashScope 账户欠费时 ASR/TTS 会返回 HTTP 400 Arrearage，Host 表现为 `lan_voice_asr_error=protocol`——此时应提示用户去百炼控制台充值，而不是改代码。
