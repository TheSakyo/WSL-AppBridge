# Setup WSLD + GWSL (Environnement Avancé)

Ce guide explique comment configurer un environnement X11 contrôlé pour WSL-AppBridge en utilisant WSLD et GWSL à la place de WSLg.

---

## 🧠 Vue d’ensemble

Ce setup remplace WSLg par une stack entièrement contrôlée :

* **WSLD** → backend X11 dans WSL
* **GWSL** → serveur d’affichage Windows
* **WSL-AppBridge** → couche d’intégration des applications

---

## 🎯 Pourquoi utiliser ce setup

* Contrôle total du pipeline graphique
* Aucun conflit avec WSLg
* Comportement GUI stable et prévisible
* Meilleure compatibilité avec des workflows personnalisés

---

## ⚙️ 1. Installer les dépendances

```bash
sudo apt update
sudo apt install -y \
  x11-utils \
  iptables \
  cargo
```

---

## ⚙️ 2. Installer WSLD

```bash
cargo install --locked --git https://github.com/nbdd0121/wsld wsld
```

---

## ⚙️ 3. Configurer WSLD

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

## ⚙️ 4. Activer les capacités

```bash
sudo setcap cap_sys_time+eip ~/.cargo/bin/wsld
```

---

## ⚙️ 5. Activer le service systemd

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

## ⚙️ 6. Configurer l’environnement

Ajouter dans `.bashrc` :

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

## ⚙️ 7. Installer wsldhost (côté Windows)

```powershell
cargo install --locked --git https://github.com/nbdd0121/wsld wsldhost
```

### Configuration au démarrage

1. Aller dans :
`C:\Users\<votre-utilisateur>\.cargo\bin`

2. Créer un raccourci vers :
`wsldhost.exe`

3. Le placer dans :
`C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup`

---

## ⚙️ 8. Installer GWSL

* Installer depuis le Microsoft Store
* Activer :
  * mode multi-fenêtres
  * démarrage automatique du serveur X

---

## ⚙️ 9. Désactiver WSLg

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

## 🧪 10. Tester X11

```bash
echo $DISPLAY
# Attendu :0

# Optionnel (nécessite x11-apps)
xclock
```

---

## 🎯 Résultat

Vous avez maintenant :

* Un environnement X11 fonctionnel
* Aucun usage de WSLg
* Une base stable pour WSL-AppBridge

---

## ⚠️ Notes

* Pas d’accélération GPU (rendu logiciel)
* Certaines applications GNOME peuvent être instables
* Préférer des applications légères (Thunar, etc.)
