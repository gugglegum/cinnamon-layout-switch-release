#!/bin/bash

: "${HOME:?HOME is not set}"

readonly CONFIG_FILE="${KB_LAYOUT_SWITCH_CONFIG:-$HOME/.config/cinnamon-layout-switch-release.conf}"
readonly DBUS_DEST="org.Cinnamon"
readonly DBUS_OBJECT_PATH="/org/Cinnamon"
readonly DBUS_INTERFACE="org.Cinnamon"
readonly NEXT_SWITCHER_JS="imports.ui.keyboardManager.getInputSourceManager()._modifiersSwitcher(false)"

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

load_config

readonly KEYBOARD_NAME="${KB_LAYOUT_SWITCH_KEYBOARD_NAME:-AT Translated Set 2 keyboard}"
readonly FALLBACK_KEYBOARD_NAME="${KB_LAYOUT_SWITCH_FALLBACK_KEYBOARD_NAME:-Virtual core keyboard}"
readonly DEBUG="${KB_LAYOUT_SWITCH_DEBUG:-0}"
readonly LOCK_FILE="${KB_LAYOUT_SWITCH_LOCK_FILE:-${XDG_RUNTIME_DIR:-/tmp}/kb-layout-switch-release.lock}"

readonly KEY_LEFT_CTRL=37
readonly KEY_LEFT_ALT=64
readonly KEY_LEFT_SHIFT=50
readonly KEY_RIGHT_CTRL=105
readonly KEY_RIGHT_ALT=108
readonly KEY_RIGHT_SHIFT=62

switch_sequences=(
    "Ctrl_Down Shift_Down Ctrl_Up"
    "Ctrl_Down Shift_Down Shift_Up"
    "Shift_Down Ctrl_Down Ctrl_Up"
    "Shift_Down Ctrl_Down Shift_Up"
    "Alt_Down Shift_Down Alt_Up"
    "Alt_Down Shift_Down Shift_Up"
    "Shift_Down Alt_Down Alt_Up"
    "Shift_Down Alt_Down Shift_Up"
)

buffer=()

log_debug() {
    if [[ "$DEBUG" == "1" ]]; then
        echo "$*" >&2
    fi
}

resolve_gdbus_cmd() {
    if command -v gdbus >/dev/null 2>&1; then
        command -v gdbus
        return 0
    fi

    echo "Cannot find gdbus." >&2
    return 1
}

acquire_lock() {
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log_debug "Another kb-layout-switch-release instance is already running"
        exit 0
    fi
}

resolve_keyboard_id() {
    local id

    if [[ -n "${KB_LAYOUT_SWITCH_KEYBOARD_ID:-}" ]]; then
        printf '%s\n' "$KB_LAYOUT_SWITCH_KEYBOARD_ID"
        return 0
    fi

    id=$(xinput list --id-only "$KEYBOARD_NAME" 2>/dev/null | head -n 1)
    if [[ -n "$id" ]]; then
        printf '%s\n' "$id"
        return 0
    fi

    id=$(xinput list --id-only "$FALLBACK_KEYBOARD_NAME" 2>/dev/null | head -n 1)
    if [[ -n "$id" ]]; then
        printf '%s\n' "$id"
        return 0
    fi

    echo "Cannot resolve keyboard id for xinput test." >&2
    return 1
}

switch_layout() {
    "$GDBUS_CMD" call --session \
        --dest "$DBUS_DEST" \
        --object-path "$DBUS_OBJECT_PATH" \
        --method "$DBUS_INTERFACE.Eval" \
        "$NEXT_SWITCHER_JS" >/dev/null 2>&1
}

map_event() {
    local event_type="$1"
    local keycode="$2"

    case "$event_type:$keycode" in
        press:$KEY_LEFT_CTRL|press:$KEY_RIGHT_CTRL) printf '%s\n' "Ctrl_Down" ;;
        release:$KEY_LEFT_CTRL|release:$KEY_RIGHT_CTRL) printf '%s\n' "Ctrl_Up" ;;
        press:$KEY_LEFT_ALT|press:$KEY_RIGHT_ALT) printf '%s\n' "Alt_Down" ;;
        release:$KEY_LEFT_ALT|release:$KEY_RIGHT_ALT) printf '%s\n' "Alt_Up" ;;
        press:$KEY_LEFT_SHIFT|press:$KEY_RIGHT_SHIFT) printf '%s\n' "Shift_Down" ;;
        release:$KEY_LEFT_SHIFT|release:$KEY_RIGHT_SHIFT) printf '%s\n' "Shift_Up" ;;
        press:*) printf '%s\n' "Other_Down" ;;
        release:*) printf '%s\n' "Other_Up" ;;
        *) return 1 ;;
    esac
}

check_sequence() {
    if [[ ${#buffer[@]} -ne 3 ]]; then
        return
    fi

    for switch_sequence in "${switch_sequences[@]}"; do
        if [[ "${buffer[*]}" == "$switch_sequence" ]]; then
            log_debug "--- KEYBOARD SWITCH ---"
            buffer=()

            if ! switch_layout; then
                echo "Layout switch failed" >&2
            fi
            return
        fi
    done
}

readonly GDBUS_CMD="$(resolve_gdbus_cmd 2>/dev/null || true)"
if [[ -z "$GDBUS_CMD" ]]; then
    echo "Cannot find gdbus." >&2
    exit 1
fi
readonly KEYBOARD_ID="$(resolve_keyboard_id)" || exit 1
acquire_lock
log_debug "Using config file $CONFIG_FILE"
log_debug "Listening on keyboard id $KEYBOARD_ID"
log_debug "Using Cinnamon Eval backend via gdbus: $GDBUS_CMD"

while read -r line; do
    event=""
    log_debug "$line"

    if [[ "$line" =~ ^key[[:space:]]+(press|release)[[:space:]]+([0-9]+)$ ]]; then
        event="$(map_event "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")" || continue
    else
        continue
    fi

    log_debug "$event"
    buffer+=("$event")

    if [[ ${#buffer[@]} -gt 3 ]]; then
        buffer=("${buffer[@]: -3}")
    fi

    if [[ "${buffer[*]}" == *"Other_Down"* ]] || [[ "${buffer[*]}" == *"Other_Up"* ]]; then
        buffer=()
    fi

    check_sequence
done < <(xinput test "$KEYBOARD_ID")
