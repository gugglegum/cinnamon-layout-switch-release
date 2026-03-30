#!/bin/sh

set -eu

BIN_DIR=${INSTALL_BIN_DIR:-/usr/local/bin}
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

AUTOSTART_FILE="$TARGET_HOME/.config/autostart/kb-layout-switch-release.desktop"

run_as_root rm -f "$HELPER_DST" "$LISTENER_DST"
rm -f "$AUTOSTART_FILE"

cat <<EOF
Removed:
  $HELPER_DST
  $LISTENER_DST
  $AUTOSTART_FILE
EOF
