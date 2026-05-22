#!/usr/bin/env bash
# =============================================================================
#  WSL-AppBridge — Linux-side launch wrapper
# =============================================================================
#  Sets up the runtime environment for GUI apps started from Windows .lnk
#  shortcuts. Centralises every fix needed when running outside WSLg:
#
#    * X11 display          — provided by GWSL / VcXsrv on Windows
#    * Audio (PulseAudio)   — TCP server hosted on Windows (PulseAudio-for-Win)
#    * DBus session         — started on demand (notifications, tray, menus)
#    * Wayland-only bypass  — force X11 backend for Gtk / Qt / SDL / Mozilla
#
#  Invoked as:  ~/.wsl-appbridge/launch.sh <argv of the .desktop Exec line>
# =============================================================================

# ---- X11 --------------------------------------------------------------------
# Override via the parent env (Install.ps1 -Display :0.0 etc).
export DISPLAY="${DISPLAY:-:0}"
# Older Mesa builds prefer indirect rendering when the X server is remote.
# Harmless when not needed, prevents some 'GLX not supported' errors on GWSL.
export LIBGL_ALWAYS_INDIRECT="${LIBGL_ALWAYS_INDIRECT:-1}"

# ---- Audio ------------------------------------------------------------------
# PulseAudio-for-Windows (or pulseaudio-server-wsl) listens on TCP:4713 by
# convention. If nothing is reachable, apps just stay silent — no error.
export PULSE_SERVER="${PULSE_SERVER:-tcp:127.0.0.1:4713}"

# ---- Force X11 backends -----------------------------------------------------
# Wayland-only Gtk4 / Qt6 builds refuse to start when $WAYLAND_DISPLAY is unset;
# pinning the backend makes them fall back to X11 cleanly.
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"
export CLUTTER_BACKEND="${CLUTTER_BACKEND:-x11}"
export MOZ_ENABLE_WAYLAND=0
# Silence noisy a11y warnings on WSL distros that lack at-spi.
export NO_AT_BRIDGE=1

# ---- DBus session -----------------------------------------------------------
# When no bus is active, dbus-run-session spawns one for the lifetime of $@
# and tears it down on exit. Fall back to direct exec if the tool is missing —
# the app launches, just without notifications / tray.
if [ -z "${DBUS_SESSION_BUS_ADDRESS}" ] && command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "$@"
fi
exec "$@"
