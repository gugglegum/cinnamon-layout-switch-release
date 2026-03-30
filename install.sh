#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN_DIR=${INSTALL_BIN_DIR:-/usr/local/bin}
HELPER_SRC="$SCRIPT_DIR/bin/cinnamon-xkb-switch"
LISTENER_SRC="$SCRIPT_DIR/bin/kb-layout-switch-release.sh"
DESKTOP_TEMPLATE="$SCRIPT_DIR/autostart/kb-layout-switch-release.desktop.in"
HELPER_DST="$BIN_DIR/cinnamon-xkb-switch"
LISTENER_DST="$BIN_DIR/kb-layout-switch-release.sh"

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

TARGET_USER=${TARGET_USER:-${SUDO_USER:-${USER:-}}}
if [ -z "$TARGET_USER" ]; then
    echo "Cannot detect target user. Set TARGET_USER=username and run again." >&2
    exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [ -z "$TARGET_HOME" ]; then
    echo "Cannot resolve home directory for user '$TARGET_USER'." >&2
    exit 1
fi

AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/kb-layout-switch-release.desktop"
TMP_DESKTOP=$(mktemp)
trap 'rm -f "$TMP_DESKTOP"' EXIT INT TERM

run_as_root install -d -m 755 "$BIN_DIR"
run_as_root install -m 755 "$HELPER_SRC" "$HELPER_DST"
run_as_root install -m 755 "$LISTENER_SRC" "$LISTENER_DST"

install -d -m 755 "$AUTOSTART_DIR"
sed "s|@LISTENER_PATH@|$LISTENER_DST|g" "$DESKTOP_TEMPLATE" > "$TMP_DESKTOP"
install -m 644 "$TMP_DESKTOP" "$AUTOSTART_FILE"

if [ "$(id -u)" -eq 0 ]; then
    chown "$TARGET_USER:$TARGET_USER" "$AUTOSTART_FILE"
fi

cat <<EOF
Installed:
  $HELPER_DST
  $LISTENER_DST
  $AUTOSTART_FILE

Recommended next steps:
  1. Disable Cinnamon built-in layout switching shortcuts if you want release-based switching only:
     gsettings set org.cinnamon.desktop.keybindings.wm switch-input-source "[]"
     gsettings set org.cinnamon.desktop.keybindings.wm switch-input-source-backward "[]"
  2. Make sure you are on Cinnamon X11, not Wayland.
  3. Log out and log in again, or start the listener manually:
     $LISTENER_DST
EOF
