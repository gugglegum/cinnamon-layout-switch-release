#!/bin/bash

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
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

resolve_layout_switch_cmd() {
    if [[ -n "${LAYOUT_SWITCH_CMD:-}" ]]; then
        printf '%s\n' "$LAYOUT_SWITCH_CMD"
        return 0
    fi

    if [[ -x "$SCRIPT_DIR/cinnamon-xkb-switch" ]]; then
        printf '%s\n' "$SCRIPT_DIR/cinnamon-xkb-switch"
        return 0
    fi

    if command -v cinnamon-xkb-switch >/dev/null 2>&1; then
        command -v cinnamon-xkb-switch
        return 0
    fi

    echo "Cannot find cinnamon-xkb-switch. Set LAYOUT_SWITCH_CMD or install it next to this script." >&2
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

check_sequence() {
    if [[ ${#buffer[@]} -ne 3 ]]; then
        return
    fi

    for switch_sequence in "${switch_sequences[@]}"; do
        if [[ "${buffer[*]}" == "$switch_sequence" ]]; then
            log_debug "--- KEYBOARD SWITCH ---"
            buffer=()

            if ! "$LAYOUT_SWITCH_CMD" -n; then
                echo "Layout switch failed" >&2
            fi
            return
        fi
    done
}

readonly LAYOUT_SWITCH_CMD="$(resolve_layout_switch_cmd)" || exit 1
readonly KEYBOARD_ID="$(resolve_keyboard_id)" || exit 1
acquire_lock
log_debug "Listening on keyboard id $KEYBOARD_ID"

while read -r line; do
    log_debug "$line"

    event_type=$(echo "$line" | awk '{print $2}')
    keycode=$(echo "$line" | awk '{print $3}')

    event=""
    if [[ $event_type == "press" ]]; then
        if [[ $keycode == $KEY_LEFT_CTRL || $keycode == $KEY_RIGHT_CTRL ]]; then
            event="Ctrl_Down"
        elif [[ $keycode == $KEY_LEFT_ALT || $keycode == $KEY_RIGHT_ALT ]]; then
            event="Alt_Down"
        elif [[ $keycode == $KEY_LEFT_SHIFT || $keycode == $KEY_RIGHT_SHIFT ]]; then
            event="Shift_Down"
        else
            event="Other_Down"
        fi
    elif [[ $event_type == "release" ]]; then
        if [[ $keycode == $KEY_LEFT_CTRL || $keycode == $KEY_RIGHT_CTRL ]]; then
            event="Ctrl_Up"
        elif [[ $keycode == $KEY_LEFT_ALT || $keycode == $KEY_RIGHT_ALT ]]; then
            event="Alt_Up"
        elif [[ $keycode == $KEY_LEFT_SHIFT || $keycode == $KEY_RIGHT_SHIFT ]]; then
            event="Shift_Up"
        else
            event="Other_Up"
        fi
    fi

    if [[ -z "$event" ]]; then
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
