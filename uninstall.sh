#!/bin/sh

set -eu

print_help() {
    cat <<EOF
Usage: ./uninstall.sh [options]

Options:
  --user          Remove files from ~/.local/bin (default)
  --system        Remove files from /usr/local/bin
  --bin-dir PATH  Remove files from PATH
  --purge-config  Also remove ~/.config/cinnamon-layout-switch-release.conf
  -h, --help      Show this help

Environment:
  TARGET_USER       Target user for the autostart file
  INSTALL_BIN_DIR   Alternative way to set the binary install dir
EOF
}

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

DEFAULT_USER_BIN="$TARGET_HOME/.local/bin"
BIN_DIR=${INSTALL_BIN_DIR:-$DEFAULT_USER_BIN}
PURGE_CONFIG=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)
            BIN_DIR="$DEFAULT_USER_BIN"
            ;;
        --system)
            BIN_DIR="/usr/local/bin"
            ;;
        --bin-dir)
            shift
            if [ "$#" -eq 0 ]; then
                echo "--bin-dir requires a path." >&2
                exit 1
            fi
            BIN_DIR="$1"
            ;;
        --purge-config)
            PURGE_CONFIG=1
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help >&2
            exit 1
            ;;
    esac
    shift
done

LISTENER_DST="$BIN_DIR/kb-layout-switch-release.sh"
AUTOSTART_FILE="$TARGET_HOME/.config/autostart/kb-layout-switch-release.desktop"
CONFIG_FILE="$TARGET_HOME/.config/cinnamon-layout-switch-release.conf"

case "$BIN_DIR" in
    "$TARGET_HOME"|"$TARGET_HOME"/*)
        rm -f "$LISTENER_DST"
        ;;
    *)
        run_as_root rm -f "$LISTENER_DST"
        ;;
esac

rm -f "$AUTOSTART_FILE"

if [ "$PURGE_CONFIG" -eq 1 ]; then
    rm -f "$CONFIG_FILE"
fi

cat <<EOF
Removed:
  $LISTENER_DST
  $AUTOSTART_FILE
EOF

if [ "$PURGE_CONFIG" -eq 1 ]; then
    cat <<EOF
  $CONFIG_FILE
EOF
else
    cat <<EOF
Preserved config:
  $CONFIG_FILE
EOF
fi
