#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HELPER_SRC="$SCRIPT_DIR/bin/cinnamon-xkb-switch"
LISTENER_SRC="$SCRIPT_DIR/bin/kb-layout-switch-release.sh"
DESKTOP_TEMPLATE="$SCRIPT_DIR/autostart/kb-layout-switch-release.desktop.in"

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

print_help() {
    cat <<EOF
Usage: ./install.sh [options]

Options:
  --user          Install into ~/.local/bin (default)
  --system        Install into /usr/local/bin
  --bin-dir PATH  Install binaries into PATH
  -i, --interactive
                  Prompt for the installation target
  -h, --help      Show this help

Environment:
  TARGET_USER       Target user for the autostart file
  INSTALL_BIN_DIR   Alternative way to set the binary install dir
EOF
}

resolve_target_user() {
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
}

path_is_under_target_home() {
    case "$1" in
        "$TARGET_HOME"|"$TARGET_HOME"/*) return 0 ;;
        *) return 1 ;;
    esac
}

install_file() {
    destination_check="$1"
    shift

    if path_is_under_target_home "$destination_check"; then
        install "$@"
    else
        run_as_root install "$@"
    fi
}

install_dir() {
    if path_is_under_target_home "$1"; then
        install -d -m 755 "$1"
    else
        run_as_root install -d -m 755 "$1"
    fi
}

choose_bin_dir() {
    if [ ! -t 0 ]; then
        echo "Interactive mode requires a TTY." >&2
        exit 1
    fi

    printf '%s\n' "Select installation target for executable files:"
    printf '  1) %s (Recommended)\n' "$DEFAULT_USER_BIN"
    printf '  2) /usr/local/bin\n'
    printf '  3) Custom path\n'
    printf 'Choice [1]: '
    read -r choice

    case "${choice:-1}" in
        1)
            BIN_DIR="$DEFAULT_USER_BIN"
            ;;
        2)
            BIN_DIR="/usr/local/bin"
            ;;
        3)
            printf 'Enter full path: '
            read -r BIN_DIR
            if [ -z "$BIN_DIR" ]; then
                echo "Custom path cannot be empty." >&2
                exit 1
            fi
            ;;
        *)
            echo "Invalid choice: $choice" >&2
            exit 1
            ;;
    esac
}

resolve_target_user
DEFAULT_USER_BIN="$TARGET_HOME/.local/bin"
BIN_DIR=${INSTALL_BIN_DIR:-$DEFAULT_USER_BIN}
INTERACTIVE=0
BIN_DIR_EXPLICIT=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --user)
            BIN_DIR="$DEFAULT_USER_BIN"
            BIN_DIR_EXPLICIT=1
            ;;
        --system)
            BIN_DIR="/usr/local/bin"
            BIN_DIR_EXPLICIT=1
            ;;
        --bin-dir)
            shift
            if [ "$#" -eq 0 ]; then
                echo "--bin-dir requires a path." >&2
                exit 1
            fi
            BIN_DIR="$1"
            BIN_DIR_EXPLICIT=1
            ;;
        -i|--interactive)
            INTERACTIVE=1
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

if [ "$INTERACTIVE" -eq 1 ] && [ "$BIN_DIR_EXPLICIT" -eq 0 ]; then
    choose_bin_dir
fi

HELPER_DST="$BIN_DIR/cinnamon-xkb-switch"
LISTENER_DST="$BIN_DIR/kb-layout-switch-release.sh"
AUTOSTART_DIR="$TARGET_HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/kb-layout-switch-release.desktop"
TMP_DESKTOP=$(mktemp)
trap 'rm -f "$TMP_DESKTOP"' EXIT INT TERM

install_dir "$BIN_DIR"
install_file "$BIN_DIR" -m 755 "$HELPER_SRC" "$HELPER_DST"
install_file "$BIN_DIR" -m 755 "$LISTENER_SRC" "$LISTENER_DST"

install_dir "$AUTOSTART_DIR"
sed "s|@LISTENER_PATH@|$LISTENER_DST|g" "$DESKTOP_TEMPLATE" > "$TMP_DESKTOP"
install -m 644 "$TMP_DESKTOP" "$AUTOSTART_FILE"

if [ "$(id -u)" -eq 0 ]; then
    if path_is_under_target_home "$BIN_DIR"; then
        chown "$TARGET_USER:$TARGET_USER" "$BIN_DIR" "$HELPER_DST" "$LISTENER_DST"
    fi
    chown "$TARGET_USER:$TARGET_USER" "$AUTOSTART_DIR" "$AUTOSTART_FILE"
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

if [ "$BIN_DIR" = "$DEFAULT_USER_BIN" ]; then
    cat <<EOF
  4. If "$DEFAULT_USER_BIN" is not yet in your PATH for the current shell, log in again before using:
     $HELPER_DST
EOF
fi
