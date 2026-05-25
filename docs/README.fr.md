# WSL-AppBridge — Documentation française

Raccourcis Windows natifs pour les applications GUI Linux de WSL2, sans WSLg.

[← Retour au README racine](../README.md) · [English version](README.en.md)

---

## Sommaire

1. [Vue d'ensemble](#vue-densemble)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Setup multi-distro](#setup-multi-distro)
5. [Dépendances Linux](#dépendances-linux)
6. [Audio (PulseAudio sur TCP)](#audio-pulseaudio-sur-tcp)
7. [Architecture](#architecture)
8. [Structure du projet](#structure-du-projet)
9. [Dépannage](#dépannage)
10. [Désinstallation](#désinstallation)
11. [Fonctionnement interne](#fonctionnement-interne)

---

## Vue d'ensemble

WSL-AppBridge scanne ta distribution WSL pour trouver les fichiers `.desktop`
installés (les descripteurs d'applications freedesktop.org), et génère les
raccourcis Windows `.lnk` correspondants dans le menu Démarrer. Chaque
raccourci lance l'application Linux via `wsl.exe` avec l'environnement
adéquat pour l'afficher côté Windows via X11 (GWSL / VcXsrv).

C'est une alternative délibérée à **WSLg**, le pont GUI officiel de Microsoft
livré avec WSL2. WSLg fonctionne mais souffre de problèmes connus : latence
de rendu, glitches d'écran noir occasionnels, contrôle limité du fenêtrage,
et bizarreries de routing audio. WSL-AppBridge contourne WSLg entièrement et
donne une stack X11 prévisible avec un contrôle explicite sur tout.

---

## Installation

### 1. Prérequis

- Windows 10 (1809 ou plus récent) ou Windows 11
- WSL2 activé avec au moins une distro installée (`wsl --install -d Debian`)
- Un serveur X11 qui tourne sur Windows. Recommandé : **[GWSL](https://opticos.github.io/gwsl/)**
  depuis le Microsoft Store (se configure tout seul). Alternative :
  **[VcXsrv](https://sourceforge.net/projects/vcxsrv/)** (lancer avec
  l'option "Disable access control" activée).

### 2. Cloner et installer

```powershell
git clone https://github.com/TheSakyo/WSL-AppBridge.git
cd WSL-AppBridge
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Debian -Display :0
```

Ce qui va :

1. Copier le payload dans `%LOCALAPPDATA%\WSL-AppBridge\`
2. Écrire une config par-distro dans `%LOCALAPPDATA%\WSL-AppBridge\instances\Debian\settings.json`
3. Enregistrer deux Scheduled Tasks (`WSL-AppBridge-Sync-Debian`, `WSL-AppBridge-Watcher-Debian`)
4. Lancer une sync initiale — qui déploie aussi le wrapper dans la distro
   (`~/.wsl-appbridge/launch.sh`) et vérifie les dépendances Linux optionnelles

Tes raccourcis apparaissent dans `%APPDATA%\Microsoft\Windows\Start Menu\Programs\WSL Apps\Debian\<Catégorie>\`.

### 3. Installer les dépendances Linux optionnelles

Pour toutes les fonctionnalités (icônes SVG, icônes XPM, notifications/tray),
exécuter dans la distro :

```bash
sudo apt-get update
sudo apt-get install -y librsvg2-bin imagemagick dbus-user-session
```

L'installeur loggue la commande exacte si un de ces paquets manque.

---

## Configuration

> [!IMPORTANT]
> **Comment désactiver WSLg (Requis)**
> *   **Méthode 1 (Globale) :** Ajoutez `guiApplications=false` sous la section `[wsl2]` dans votre fichier `%USERPROFILE%\.wslconfig`.
> *   **Méthode 2 (Par distro) :** Dans votre terminal Linux, modifiez le fichier `/etc/wsl.conf` et ajoutez :
>     ```ini
>     [gui]
>     enabled=false
>     ```
>     Ensuite, redémarrez WSL avec la commande `wsl --shutdown` dans PowerShell

</br>

Tous les paramètres acceptés par `Install.ps1` :

| Paramètre | Défaut | Rôle |
| --- | --- | --- |
| `-Distro` | `Debian` | Nom de la distribution WSL |
| `-Display` | `:0` | Valeur DISPLAY X11 passée au wrapper |
| `-ShortcutRoot` | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\WSL Apps\<Distro>` | Où sont écrits les raccourcis |
| `-SkipWatcher` | (off) | Ne pas enregistrer la tâche watcher |
| `-SkipScheduledTasks` | (off) | Ne pas enregistrer de tâches (sync manuelle uniquement) |

Le fichier de config dans `%LOCALAPPDATA%\WSL-AppBridge\instances\<Distro>\settings.json`
est modifiable à la main après installation — Sync et Watcher le respectent.

---

## Setup multi-distro

Chaque appel à `Install.ps1` crée une nouvelle instance côte à côte. Exemples :

```powershell
# Instance Debian
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Debian

# Instance Ubuntu, racine de raccourcis différente
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Ubuntu

# Emplacement personnalisé
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Distro Fedora -ShortcutRoot "D:\WSL\Shortcuts\Fedora"
```

Tâches résultantes : `WSL-AppBridge-Sync-Debian`, `WSL-AppBridge-Sync-Ubuntu`,
`WSL-AppBridge-Sync-Fedora` (et les `-Watcher-*` correspondants). Elles sont
totalement indépendantes — désinstaller l'une n'affecte pas les autres.

---

## Dépendances Linux

| Outil | Paquet apt | Rôle | Sans lui |
| --- | --- | --- | --- |
| `rsvg-convert` | `librsvg2-bin` | Rastérisation SVG → PNG | Apps avec icône SVG → icône par défaut wsl.exe |
| `convert` | `imagemagick` | Fallback XPM → PNG | Apps avec icône XPM → icône par défaut wsl.exe |
| `dbus-run-session` | `dbus-user-session` | Session DBus par lancement | Pas de notifications, pas de tray, warnings Gtk possibles |

Aucune n'est obligatoire — l'app se lance dans tous les cas. Les outils
manquants dégradent uniquement des features spécifiques.

---

## Audio (PulseAudio sur TCP)

X11 ne transporte pas l'audio. Pour avoir du son depuis les apps WSL :

1. **Côté Windows** : installer un serveur PulseAudio. Options :
   - [PulseAudio for Windows (builds MSYS2)](https://www.freedesktop.org/wiki/Software/PulseAudio/Ports/Windows/) — open-source, gratuit
   - Ou tout serveur audio TCP compatible écoutant sur `127.0.0.1:4713`
2. **Dans WSL** : s'assurer que le paquet `pulseaudio-utils` est installé
   (la plupart des distros l'ont par défaut).
3. **Aucune config WSL-AppBridge nécessaire** — le wrapper exporte
   `PULSE_SERVER=tcp:127.0.0.1:4713` automatiquement.

Si aucun serveur PulseAudio n'est joignable, les apps restent muettes mais
ne crashent pas.

---

## Architecture

```
                            ┌──────────────────────────┐
                            │  Install.ps1 (one-shot)  │
                            └──────────┬───────────────┘
                                       │ déploie
                                       ▼
%LOCALAPPDATA%\WSL-AppBridge\          │
├── Sync-WSLApps.ps1   ◄── Scheduled Task: WSL-AppBridge-Sync-<Distro>
├── Watch-WSLApps.ps1  ◄── Scheduled Task: WSL-AppBridge-Watcher-<Distro>
├── modules\           ◄── WSLAppBridge.{Logger,Discovery,Icons,Shortcuts,
│                          Categories,WslSetup}.psm1
├── assets\launch.sh   ◄── déployé dans la distro à l'install + à chaque
│                          sync (self-heal)
└── instances\<Distro>\settings.json, state.json, sync.log, icons\

Dans la distro WSL :
~/.wsl-appbridge/launch.sh
    ├── set DISPLAY, PULSE_SERVER
    ├── force GDK_BACKEND=x11, QT_QPA_PLATFORM=xcb (bypass Wayland-only)
    └── démarre dbus-run-session si aucun bus actif

Cible du raccourci .lnk :
    wscript.exe Run-WSL.vbs "wsl.exe -d <Distro> --cd ~ -- env DISPLAY=:0
                            $HOME/.wsl-appbridge/launch.sh <exec>"
```

Choix de design clés :

- **Pas de `wslg.exe` nulle part** — X11 pur via GWSL/VcXsrv
- **Pont UNC pour les IO fichiers** — `\\wsl.localhost\<distro>\` (ou `\\wsl$\` sur ancienne Windows) pour lire les `.desktop` en file IO classique, sans `wsl.exe` spawné par fichier
- **Sync idempotente** — fingerprint MD5 des nom+taille+mtime de tous les `.desktop` court-circuite la passe entière quand rien n'a changé ; MD5 par raccourci dans la Description du `.lnk` évite de réécrire les raccourcis individuels
- **ICO format Vista** — payload PNG brut dans un container ICO, pas de `Bitmap.GetHicon()`, alpha complet préservé
- **Chargement modules via `[scriptblock]::Create`** — contourne le piège silencieux de PowerShell qui force le scope module pour les fichiers `.psm1` dot-sourcés

---

## Structure du projet

```
WSL-AppBridge/
├── Install.ps1                  Point d'entrée, multi-distro
├── Uninstall.ps1                Par-distro ou -All
├── Sync-WSLApps.ps1             Sync one-shot (charge modules, walk apps)
├── Watch-WSLApps.ps1            Boucle polling (60s par défaut)
├── Run-WSL.vbs                  Launcher VBS silencieux (pas de flash console)
├── assets\
│   └── launch.sh                Wrapper d'environnement in-distro
├── modules\
│   ├── WSLAppBridge.Logger.psm1
│   ├── WSLAppBridge.Categories.psm1
│   ├── WSLAppBridge.Discovery.psm1
│   ├── WSLAppBridge.WslSetup.psm1
│   ├── WSLAppBridge.Icons.psm1
│   └── WSLAppBridge.Shortcuts.psm1
└── docs\
    ├── README.en.md             Documentation anglaise
    └── README.fr.md             Ce fichier
```

---

## Dépannage

| Symptôme | Cause probable | Fix |
| --- | --- | --- |
| `Logger functions not in scope` | Install vieux, fichiers mixés | Réextraire le zip, `Uninstall.ps1 -All`, réinstaller |
| `Initialize-WABLogger is not recognized` (legacy) | Fonctions module pas exposées | Fixé dans versions récentes via chargement scriptblock |
| Raccourci ne lance rien | Serveur X11 pas démarré sur Windows | Lancer GWSL ou VcXsrv |
| Flash noir au clic | Le launcher VBS n'est pas utilisé | Relancer `Install.ps1` pour reconstruire les cibles .lnk |
| Pas d'icônes (juste pingu wsl.exe par défaut) | Icône source SVG/XPM et rastérisateur absent | `sudo apt-get install librsvg2-bin imagemagick` dans la distro |
| Notifications / tray absentes | Pas de session DBus active | `sudo apt-get install dbus-user-session` |
| App Wayland-only refuse de démarrer | Wrapper non invoqué | Vérifier que `~/.wsl-appbridge/launch.sh` existe ; Sync le redéploie au passage suivant |
| App muette | Pas de serveur PulseAudio TCP sur Windows | Installer PulseAudio for Windows (voir section Audio) |
| Apps n'apparaissent pas dans la recherche Start Menu | Lag d'indexation | Attendre ~1min, ou `Get-Process explorer \| Stop-Process -Force` |

### Logs

- Log Install / Sync : `%LOCALAPPDATA%\WSL-AppBridge\instances\<Distro>\sync.log`
- Log Watcher : `%LOCALAPPDATA%\WSL-AppBridge\instances\<Distro>\watcher.log`

### Forcer une re-sync complète

```powershell
& "$env:LOCALAPPDATA\WSL-AppBridge\Sync-WSLApps.ps1" `
    -ConfigPath "$env:LOCALAPPDATA\WSL-AppBridge\instances\Debian\settings.json" `
    -Force
```

---

## Désinstallation

Supprimer une seule instance :

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WSL-AppBridge\Uninstall.ps1" -Distro Debian
```

Tout supprimer (toutes instances + payload partagé) :

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WSL-AppBridge\Uninstall.ps1" -All
```

Garder l'arbre de raccourcis sur disque :

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WSL-AppBridge\Uninstall.ps1" -All -KeepShortcuts
```

---

## Fonctionnement interne

**Pipeline de sync** (`Sync-WSLApps.ps1`) :

1. Charger chaque module via `[scriptblock]::Create(Get-Content -Raw)` puis dot-source le scriptblock. Ça contourne le piège automatique de PowerShell qui force le scope module pour les fichiers `.psm1`.
2. Résoudre `$HOME` dans la distro en un seul appel `wsl.exe`.
3. Self-heal : si `~/.wsl-appbridge/launch.sh` manque, redéployer depuis `assets\launch.sh`.
4. Premier run uniquement : tester les deps Linux (`rsvg-convert`, `convert`, `dbus-run-session`) et logger un one-liner apt si quelque chose manque.
5. Calculer le fingerprint MD5 de tous les `.desktop` (nom + taille + mtime). Inchangé depuis le dernier `state.json` → exit.
6. Walk `/usr/share/applications`, `/usr/local/share/applications`, `~/.local/share/applications` (précédence first-match-wins). Filtrer `Type≠Application`, `NoDisplay=true`, `Hidden=true`, `Terminal=true`. Stripper les field codes freedesktop (`%f`, `%U`, …) dans `Exec`.
7. Pour chaque app :
   - Résoudre l'icône : chemin absolu → hicolor aux tailles préférées → `/usr/share/pixmaps` → tout thème sous `/usr/share/icons`.
   - Si PNG : copier + wrap en ICO format Vista.
   - Si SVG/XPM : rastériser via `rsvg-convert`/`convert`, puis wrap.
   - Construire le `.lnk` (target = `wscript.exe`, args = launcher VBS + commande wsl). Comparer la signature MD5 avec l'existant — réécrire seulement si changé.
8. Pruner les `.lnk` qui ne correspondent plus à aucune app installée ; supprimer les dossiers de catégorie vides.
9. Persister le nouveau fingerprint + compteurs dans `state.json`.

**Watcher** (`Watch-WSLApps.ps1`) : boucle infinie, calcule le fingerprint toutes les 60s, spawn `Sync-WSLApps.ps1` en sous-process quand ça change.

**Wrapper Linux** (`assets/launch.sh`) : point unique de setup d'environnement, idempotent, inoffensif quand les services (DBus, PulseAudio) ne sont pas disponibles — les apps lancent quand même, juste avec des features dégradées.
