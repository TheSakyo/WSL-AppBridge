# WSL-AppBridge

**EN:** Native Windows shortcuts for WSL2 Linux GUI apps — without WSLg.
Auto-discovers `.desktop` files in your distro, generates idempotent `.lnk`
shortcuts in the Start Menu, fixes audio / DBus / Wayland-only apps via an
in-distro launch wrapper.

**FR:** Raccourcis Windows natifs pour les applications GUI Linux de WSL2 —
sans WSLg. Détecte automatiquement les fichiers `.desktop` dans la distro,
génère des raccourcis `.lnk` idempotents dans le menu Démarrer, gère le son /
DBus / les apps Wayland-only via un wrapper Linux embarqué.

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Platform: Windows 10/11 + WSL2" src="https://img.shields.io/badge/platform-Windows%2010%2F11%20%2B%20WSL2-0078D6">
  <img alt="PowerShell 5.1 / 7+" src="https://img.shields.io/badge/PowerShell-5.1%20%2F%207%2B-012456">
</p>

---

## 🌐 Detailed Documentation / Documentation Détaillée

- [English](docs/README.en.md)
- [Français](docs/README.fr.md)

---

## ⚡ Quick start / Démarrage rapide

> [!IMPORTANT]
> **EN:** To bypass WSLg, you must disable it globally by adding `guiApplications=false` under the `[wsl2]` section in your `%USERPROFILE%\.wslconfig` file.
>
> **FR:** Pour contourner WSLg, vous devez le désactiver globalement en ajoutant `guiApplications=false` sous la section `[wsl2]` dans votre fichier `%USERPROFILE%\.wslconfig`.

```powershell
git clone https://github.com/TheSakyo/WSL-AppBridge.git
cd WSL-AppBridge
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Debian -Display :0
```

> **EN:** Shortcuts land in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\WSL Apps\<Distro>\`.
> Two Scheduled Tasks (sync at logon + daily noon, watcher polling every 60s)
> keep them in sync with what's installed inside the distro.
>
> **FR:** Les raccourcis sont placés dans `%APPDATA%\Microsoft\Windows\Start Menu\Programs\WSL Apps\<Distro>\`.
> Deux Scheduled Tasks (sync au logon + quotidienne à midi, watcher polling
> toutes les 60s) maintiennent la synchronisation avec ce qui est installé
> dans la distro.

---

## 🧠 Why / Pourquoi

> **EN:** WSLg works but ships with notable lag, occasional rendering glitches,
> and limited control over windowing. This tool bypasses WSLg entirely by
> routing apps through GWSL / VcXsrv (X11), with a Linux-side wrapper handling
> the gaps WSLg covered automatically: audio (PulseAudio over TCP), DBus
> sessions (notifications, tray icons), and Wayland-only Gtk4/Qt6 fallbacks.
>
> **FR:** WSLg fonctionne mais souffre de latence notable, de glitches de
> rendu occasionnels, et d'un contrôle limité sur le fenêtrage. Cet outil
> contourne WSLg entièrement en routant les apps via GWSL / VcXsrv (X11),
> avec un wrapper Linux qui gère ce que WSLg couvrait automatiquement :
> l'audio (PulseAudio sur TCP), les sessions DBus (notifications, tray),
> et le fallback X11 pour les apps Gtk4/Qt6 Wayland-only.

---

## 🏗️ Architecture

> **EN:** Modular PowerShell payload (Logger / Discovery / Icons / Shortcuts /
> WslSetup / Categories) + a shared `launch.sh` deployed inside the distro.
> Discovery reads `.desktop` files via the `\\wsl.localhost\` UNC bridge
> (no per-file `wsl.exe` calls — orders of magnitude faster). Icon pipeline
> wraps PNGs in Vista-format ICO containers, rasterizes SVG via `rsvg-convert`
> and XPM via ImageMagick. Shortcuts target `wscript.exe` + a VBS launcher
> for true silent execution (no console flash).
>
> **FR:** Payload PowerShell modulaire (Logger / Discovery / Icons / Shortcuts
> / WslSetup / Categories) + un `launch.sh` partagé déployé dans la distro.
> La découverte lit les fichiers `.desktop` via le pont UNC
> `\\wsl.localhost\` (aucun appel `wsl.exe` par fichier — des ordres de
> grandeur plus rapide). Le pipeline d'icônes encapsule les PNG dans des
> containers ICO format Vista, rastérise les SVG via `rsvg-convert` et les
> XPM via ImageMagick. Les raccourcis ciblent `wscript.exe` + un launcher
> VBS pour une exécution réellement silencieuse (pas de flash console).

---

## ✨ Features / Fonctionnalités

| EN | FR |
| --- | --- |
| Multi-distro side-by-side installs | Installation multi-distro côte à côte |
| Idempotent sync (MD5 fingerprint short-circuit) | Sync idempotente (court-circuit MD5) |
| Auto-pruning of orphan shortcuts | Suppression automatique des raccourcis orphelins |
| Category-based folder layout (freedesktop spec) | Arborescence par catégorie (spec freedesktop) |
| Self-healing Linux-side wrapper | Wrapper Linux auto-réparant |
| Polling watcher (60s default) | Watcher polling (60s par défaut) |
| PulseAudio / DBus / Wayland workarounds | Workarounds PulseAudio / DBus / Wayland |
| Zero-flash silent launch | Lancement silencieux sans flash |

---

## 🛠️ Requirements / Prérequis

### English
- Windows 10 (1809+) or Windows 11
- WSL2 with at least one Linux distribution
- X11 server on Windows: [GWSL](https://opticos.github.io/gwsl/) (recommended) or [VcXsrv](https://sourceforge.net/projects/vcxsrv/)
- Optional for full features (apt-get installable inside WSL):
  - `librsvg2-bin` — SVG icon rasterization
  - `imagemagick` — XPM icon fallback
  - `dbus-user-session` — notifications and tray icons
- Optional for audio: [PulseAudio for Windows](https://www.freedesktop.org/wiki/Software/PulseAudio/Ports/Windows/)

### Français
- Windows 10 (1809+) ou Windows 11
- WSL2 avec au moins une distribution Linux installée
- Serveur X11 sur Windows : [GWSL](https://opticos.github.io/gwsl/) (recommandé) ou [VcXsrv](https://sourceforge.net/projects/vcxsrv/)
- Optionnel pour toutes les fonctionnalités (installables via apt-get dans WSL) :
  - `librsvg2-bin` — Rastérisation des icônes SVG
  - `imagemagick` — Fallback pour les icônes XPM
  - `dbus-user-session` — Notifications et icônes de la zone de notification (systray)
- Optionnel pour le son : [PulseAudio pour Windows](https://www.freedesktop.org/wiki/Software/PulseAudio/Ports/Windows/)

---

## 📜 License / Licence

[MIT](LICENSE).
