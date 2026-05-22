# WSLD + GWSL Setup (Advanced Environment)

This guide explains how to configure a controlled X11 environment for WSL-AppBridge using WSLD and GWSL instead of WSLg.

---

## 🧠 Overview

This setup replaces WSLg with a fully controlled stack:

* **WSLD** → X11 backend inside WSL
* **GWSL** → Windows display server
* **WSL-AppBridge** → application integration layer

---

## 🎯 Why use this setup

* Full control over display pipeline
* No WSLg interference
* Stable and predictable GUI behavior
* Better compatibility with custom workflows

---

## ⚙️ 1. Install dependencies

```bash
sudo apt update
sudo apt install -y \
  x11-utils \
  iptables \
  cargo
```

---

## ⚙️ 2. Install WSLD

```bash
cargo install --locked --git https://github.com/nbdd0121/wsld wsld
```

---

## ⚙️ 3. Configure WSLD

```bash
nano ~/.wsld.toml
```

```toml
[x11]
display = 0
force = true

[time]
interval = "1hr"

[ssh_agent]
ssh_auth_sock = "/tmp/.wsld/ssh_auth_sock"
```

---

## ⚙️ 4. Enable capabilities

```bash
sudo setcap cap_sys_time+eip ~/.cargo/bin/wsld
```

---

## ⚙️ 5. Enable systemd service

```bash
sudo nano /etc/systemd/system/wsld.service
```

```ini
[Unit]
Description=WSLD - X11 and Time Sync Daemon
After=network.target

[Service]
ExecStart=/home/$USER/.cargo/bin/wsld
Restart=always
User=root
AmbientCapabilities=CAP_SYS_TIME

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable wsld
sudo systemctl start wsld
```

---

## ⚙️ 6. Configure environment

Add to `.bashrc`:

```bash
# =============================================================================
# X11 DISPLAY CONFIGURATION (WSLD)
# =============================================================================

unset WAYLAND_DISPLAY
export DISPLAY=:0
export XDG_SESSION_TYPE=x11

export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
```

---

## ⚙️ 7. Install wsldhost (Windows side)

```powershell
cargo install --locked --git https://github.com/nbdd0121/wsld wsldhost
```

### Auto-start configuration

1. Go to:
`C:\Users\<your-user>\.cargo\bin`

2. Create a shortcut for:
`wsldhost.exe`

3. Place it in:
`C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup`

---

## ⚙️ 8. Install GWSL

* Install from Microsoft Store
* Enable:
  * Multiple window mode
  * Start X server on launch

---

## ⚙️ 9. Disable WSLg

```bash
sudo nano /etc/wsl.conf
```

```ini
[gui]
enabled=false
```

```powershell
wsl --shutdown
```

---

## 🧪 10. Test X11

```bash
echo $DISPLAY
# Expected: :0

# Optional (requires x11-apps)
xclock
```

---

## 🎯 Result

You now have:

* Fully functional X11 environment
* No WSLg dependency
* Stable base for WSL-AppBridge

---

## ⚠️ Notes

* No GPU acceleration (software rendering only)
* Some GNOME apps may not work reliably
* Prefer lightweight apps (Thunar, etc.)
