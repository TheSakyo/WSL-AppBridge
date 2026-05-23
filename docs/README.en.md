# WSL-AppBridge — English Documentation

Native Windows shortcuts for WSL2 Linux GUI apps, without WSLg.

[← Back to root README](../README.md) · [Version française](README.fr.md)

---

## Table of contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Multi-distro setup](#multi-distro-setup)
5. [Linux-side dependencies](#linux-side-dependencies)
6. [Audio (PulseAudio over TCP)](#audio-pulseaudio-over-tcp)
7. [Architecture](#architecture)
8. [Project layout](#project-layout)
9. [Troubleshooting](#troubleshooting)
10. [Uninstall](#uninstall)
11. [How it works internally](#how-it-works-internally)

---

## Overview

WSL-AppBridge scans your WSL distribution for installed `.desktop` files
(the freedesktop.org application descriptors), and generates equivalent
Windows `.lnk` shortcuts in the Start Menu. Each shortcut launches the Linux
app through `wsl.exe` with the right environment to display on Windows via
X11 (GWSL / VcXsrv).

It is a deliberate alternative to **WSLg**, the official Windows GUI bridge
that Microsoft bundles with WSL2. WSLg works but has known issues: rendering
lag, occasional black-screen glitches, limited fenestration control, and
audio routing quirks. WSL-AppBridge bypasses WSLg entirely and gives you a
predictable X11 stack with explicit control over what goes where.

---

## Installation

### 1. Prerequisites

- Windows 10 (1809 or later) or Windows 11
- WSL2 enabled with at least one distro installed (`wsl --install -d Debian`)
- An X11 server running on Windows. Recommended: **[GWSL](https://opticos.github.io/gwsl/)**
  from the Microsoft Store (sets up automatically). Alternative:
  **[VcXsrv](https://sourceforge.net/projects/vcxsrv/)** (launch with
  "Disable access control" enabled).

### 2. Clone and install

```powershell
git clone https://github.com/TheSakyo/WSL-AppBridge.git
cd WSL-AppBridge
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Debian -Display :0
```

This will:

1. Copy the payload to `%LOCALAPPDATA%\WSL-AppBridge\`
2. Write a per-distro config under `%LOCALAPPDATA%\WSL-AppBridge\instances\Debian\settings.json`
3. Register two Scheduled Tasks (`WSL-AppBridge-Sync-Debian`, `WSL-AppBridge-Watcher-Debian`)
4. Run an initial sync — which also deploys the in-distro wrapper
   (`~/.wsl-appbridge/launch.sh`) and probes optional Linux dependencies

Your shortcuts appear in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\WSL Apps\Debian\<Category>\`.

### 3. Install Linux-side optional dependencies

For full features (SVG icons, XPM icons, notifications/tray), run inside
the distro:

```bash
sudo apt-get update
sudo apt-get install -y librsvg2-bin imagemagick dbus-user-session
```

The installer logs the exact command if any of these is missing.

---

## Configuration

> [!IMPORTANT]
> **How to disable WSLg (Required)**
> *   **Method 1 (Global):** Add `guiApplications=false` under the `[wsl2]` section in your `%USERPROFILE%\.wslconfig` file.
> *   **Method 2 (Per-distro):** Inside your Linux terminal, edit `/etc/wsl.conf` and add:
>     ```ini
>     [gui]
>     enabled=false
>     ```
>     Then restart WSL using `wsl --shutdown` in PowerShell.

</br>

Every parameter accepted by `Install.ps1`:

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-Distro` | `Debian` | WSL distribution name |
| `-Display` | `:0` | X11 DISPLAY value passed to the wrapper |
| `-ShortcutRoot` | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\WSL Apps\<Distro>` | Where shortcuts are written |
| `-SkipWatcher` | (off) | Don't register the polling watcher task |
| `-SkipScheduledTasks` | (off) | Don't register any tasks (manual sync only) |

The config file at `%LOCALAPPDATA%\WSL-AppBridge\instances\<Distro>\settings.json`
can be edited manually after install — Sync and Watcher both honour it.

---

## Multi-distro setup

Each `Install.ps1` invocation creates a new instance side by side. Examples:

```powershell
# Debian instance
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Debian

# Ubuntu instance, different shortcut root
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Ubuntu

# Custom location
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Fedora `
    -ShortcutRoot "D:\WSL\Shortcuts\Fedora"
```

Resulting tasks: `WSL-AppBridge-Sync-Debian`, `WSL-AppBridge-Sync-Ubuntu`,
`WSL-AppBridge-Sync-Fedora` (and matching `-Watcher-*`). They are fully
independent — uninstalling one doesn't affect the others.

---

## Linux-side dependencies

| Tool | apt package | Used for | Without it |
| --- | --- | --- | --- |
| `rsvg-convert` | `librsvg2-bin` | SVG → PNG icon rasterization | Apps with SVG icons get the default wsl.exe icon |
| `convert` | `imagemagick` | XPM → PNG icon fallback | Apps with XPM icons get the default wsl.exe icon |
| `dbus-run-session` | `dbus-user-session` | DBus session bus per launch | No desktop notifications, no tray, possible Gtk warnings |

None are mandatory — the app launches in all cases. Missing tools only
degrade specific features.

---

## Audio (PulseAudio over TCP)

X11 itself does not carry audio. To hear sound from WSL apps:

1. **On Windows**: install a PulseAudio server. Options:
   - [PulseAudio for Windows (MSYS2 builds)](https://www.freedesktop.org/wiki/Software/PulseAudio/Ports/Windows/) — open-source, free
   - Or any compatible TCP audio server listening on `127.0.0.1:4713`
2. **Inside WSL**: ensure the `pulseaudio-utils` package is installed
   (most distros have it preinstalled).
3. **No config needed in WSL-AppBridge** — the wrapper exports
   `PULSE_SERVER=tcp:127.0.0.1:4713` automatically.

If no PulseAudio server is reachable, apps stay silent but do not error.

---

## Architecture

```
                            ┌──────────────────────────┐
                            │  Install.ps1 (one-shot)  │
                            └──────────┬───────────────┘
                                       │ deploys
                                       ▼
%LOCALAPPDATA%\WSL-AppBridge\          │
├── Sync-WSLApps.ps1   ◄── Scheduled Task: WSL-AppBridge-Sync-<Distro>
├── Watch-WSLApps.ps1  ◄── Scheduled Task: WSL-AppBridge-Watcher-<Distro>
├── modules\           ◄── WSLAppBridge.{Logger,Discovery,Icons,Shortcuts,
│                          Categories,WslSetup}.psm1
├── assets\launch.sh   ◄── deployed into the distro at install + on each
│                          sync (self-heal)
└── instances\<Distro>\settings.json, state.json, sync.log, icons\

In the WSL distro:
~/.wsl-appbridge/launch.sh
    ├── sets DISPLAY, PULSE_SERVER
    ├── forces GDK_BACKEND=x11, QT_QPA_PLATFORM=xcb (Wayland-only bypass)
    └── starts dbus-run-session if no bus is active

Shortcut .lnk target:
    wscript.exe Run-WSL.vbs "wsl.exe -d <Distro> --cd ~ -- env DISPLAY=:0
                            $HOME/.wsl-appbridge/launch.sh <exec>"
```

Key design choices:

- **No `wslg.exe` anywhere** — pure X11 via GWSL/VcXsrv
- **UNC bridge for file IO** — `\\wsl.localhost\<distro>\` (or `\\wsl$\` on older Windows) so we read `.desktop` files via plain file IO, no `wsl.exe` spawned per file
- **Idempotent sync** — MD5 fingerprint of every `.desktop` file's name+size+mtime short-circuits the whole pass when nothing changed; per-shortcut MD5 in the `.lnk` Description avoids rewriting individual shortcuts
- **Vista-format ICO** — raw PNG payload inside an ICO container, no Bitmap.GetHicon() resampling, full alpha preserved
- **Module loading via `[scriptblock]::Create`** — avoids PowerShell's silent `.psm1` module-scope trap when dot-sourcing across script boundaries

---

## Project layout

```
WSL-AppBridge/
├── Install.ps1                  Entry point, multi-distro aware
├── Uninstall.ps1                Per-distro or -All
├── Sync-WSLApps.ps1             One-shot sync (loads modules, walks apps)
├── Watch-WSLApps.ps1            Polling loop (default 60s)
├── Run-WSL.vbs                  Silent VBS launcher (no console flash)
├── assets\
│   └── launch.sh                In-distro environment wrapper
├── modules\
│   ├── WSLAppBridge.Logger.psm1
│   ├── WSLAppBridge.Categories.psm1
│   ├── WSLAppBridge.Discovery.psm1
│   ├── WSLAppBridge.WslSetup.psm1
│   ├── WSLAppBridge.Icons.psm1
│   └── WSLAppBridge.Shortcuts.psm1
└── docs\
    ├── README.en.md             This file
    └── README.fr.md             Documentation française
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Logger functions not in scope` | Stale install, mixed-version files | Re-extract the zip, run `Uninstall.ps1 -All`, reinstall |
| `Initialize-WABLogger is not recognized` (legacy) | Module functions not exposed in current scope | This is fixed in current versions via scriptblock loading |
| Shortcut launches nothing | X11 server not running on Windows | Start GWSL or VcXsrv |
| Black flash on shortcut click | The VBS launcher isn't being used | Re-run `Install.ps1` so the .lnk targets are rebuilt |
| No icons (just default wsl.exe pingu) | Icon source is SVG/XPM and the rasterizer isn't installed | `sudo apt-get install librsvg2-bin imagemagick` inside the distro |
| Notifications / tray missing | No DBus session active | `sudo apt-get install dbus-user-session` |
| Wayland-only app refuses to start | Wrapper isn't being invoked | Check `~/.wsl-appbridge/launch.sh` exists in the distro; Sync auto-redeploys on next pass |
| App muted | No PulseAudio TCP server on Windows | Install PulseAudio for Windows (see Audio section) |
| Apps don't appear in Start Menu search | Search index lag | Wait ~1min, or `Get-Process explorer \| Stop-Process -Force` |

### Logs

- Install / Sync log: `%LOCALAPPDATA%\WSL-AppBridge\instances\<Distro>\sync.log`
- Watcher log: `%LOCALAPPDATA%\WSL-AppBridge\instances\<Distro>\watcher.log`

### Force a full re-sync

```powershell
& "$env:LOCALAPPDATA\WSL-AppBridge\Sync-WSLApps.ps1" `
    -ConfigPath "$env:LOCALAPPDATA\WSL-AppBridge\instances\Debian\settings.json" `
    -Force
```

---

## Uninstall

Remove one instance only:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WSL-AppBridge\Uninstall.ps1" -Distro Debian
```

Remove everything (all instances + shared payload):

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WSL-AppBridge\Uninstall.ps1" -All
```

Keep the shortcut tree on disk:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WSL-AppBridge\Uninstall.ps1" -All -KeepShortcuts
```

---

## How it works internally

**Sync pipeline** (`Sync-WSLApps.ps1`):

1. Load every module via `[scriptblock]::Create(Get-Content -Raw)` then dot-source the scriptblock. This bypasses PowerShell's automatic module-scope trap on `.psm1` extensions.
2. Resolve `$HOME` inside the distro with a single `wsl.exe` call.
3. Self-heal: if `~/.wsl-appbridge/launch.sh` is missing, redeploy from `assets\launch.sh`.
4. First-run only: probe Linux deps (`rsvg-convert`, `convert`, `dbus-run-session`) and log a single apt one-liner if any is missing.
5. Compute MD5 fingerprint of all `.desktop` files (name + size + mtime). If unchanged since last `state.json`, exit.
6. Walk `/usr/share/applications`, `/usr/local/share/applications`, `~/.local/share/applications` (first-match-wins precedence). Filter out `Type≠Application`, `NoDisplay=true`, `Hidden=true`, `Terminal=true`. Strip freedesktop field codes (`%f`, `%U`, …) from `Exec`.
7. For each app:
   - Resolve icon: absolute path → hicolor at preferred sizes → `/usr/share/pixmaps` → any theme under `/usr/share/icons`.
   - If PNG: copy + wrap into Vista-format ICO.
   - If SVG/XPM: rasterize via `rsvg-convert`/`convert`, then wrap.
   - Build the `.lnk` (target = `wscript.exe`, args = VBS launcher + wsl command). Compare MD5 signature with existing — rewrite only if changed.
8. Prune `.lnk` files no longer corresponding to any installed app; drop empty category folders.
9. Persist new fingerprint + counters to `state.json`.

**Watcher** (`Watch-WSLApps.ps1`): infinite loop, computes the fingerprint every 60s, spawns `Sync-WSLApps.ps1` as a subprocess when it changes.

**Linux wrapper** (`assets/launch.sh`): single point of environment setup, idempotent, harmless when services (DBus, PulseAudio) aren't available — apps still launch, just with degraded features.
