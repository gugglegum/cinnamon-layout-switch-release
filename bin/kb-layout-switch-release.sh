#!/bin/bash

: "${HOME:?HOME is not set}"

readonly SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
readonly CONFIG_FILE="${KB_LAYOUT_SWITCH_CONFIG:-$HOME/.config/cinnamon-layout-switch-release.conf}"
readonly DBUS_DEST="org.Cinnamon"
readonly DBUS_OBJECT_PATH="/org/Cinnamon"
readonly DBUS_INTERFACE="org.Cinnamon"

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

source_tuples=()
tuple_fields=()
source_indexes=()
current_source_pos=-1

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

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

extract_source_tuples() {
    local raw="$1"
    local char=""
    local current=""
    local in_quote=0
    local escape=0
    local bracket_depth=0
    local paren_depth=0
    local i

    source_tuples=()

    for ((i = 0; i < ${#raw}; i++)); do
        char="${raw:i:1}"

        if (( escape )); then
            if (( paren_depth > 0 )); then
                current+="$char"
            fi
            escape=0
            continue
        fi

        if [[ "$char" == "\\" ]]; then
            if (( paren_depth > 0 )); then
                current+="$char"
            fi
            escape=1
            continue
        fi

        if [[ "$char" == "'" ]]; then
            (( in_quote = 1 - in_quote ))
            if (( paren_depth > 0 )); then
                current+="$char"
            fi
            continue
        fi

        if (( in_quote )); then
            if (( paren_depth > 0 )); then
                current+="$char"
            fi
            continue
        fi

        case "$char" in
            '[')
                (( bracket_depth++ ))
                ;;
            ']')
                (( bracket_depth-- ))
                ;;
            '(')
                if (( bracket_depth > 0 )); then
                    if (( paren_depth == 0 )); then
                        current=""
                    fi
                    (( paren_depth++ ))
                    current+="$char"
                fi
                ;;
            ')')
                if (( paren_depth > 0 )); then
                    current+="$char"
                    (( paren_depth-- ))
                    if (( paren_depth == 0 )); then
                        source_tuples+=("$current")
                        current=""
                    fi
                fi
                ;;
            *)
                if (( paren_depth > 0 )); then
                    current+="$char"
                fi
                ;;
        esac
    done
}

split_tuple_fields() {
    local tuple="$1"
    local inner="${tuple:1:${#tuple}-2}"
    local char=""
    local current=""
    local in_quote=0
    local escape=0
    local i

    tuple_fields=()

    for ((i = 0; i < ${#inner}; i++)); do
        char="${inner:i:1}"

        if (( escape )); then
            current+="$char"
            escape=0
            continue
        fi

        if [[ "$char" == "\\" ]]; then
            current+="$char"
            escape=1
            continue
        fi

        if [[ "$char" == "'" ]]; then
            (( in_quote = 1 - in_quote ))
            current+="$char"
            continue
        fi

        if (( !in_quote )) && [[ "$char" == "," ]]; then
            tuple_fields+=("$(trim_whitespace "$current")")
            current=""
            continue
        fi

        current+="$char"
    done

    tuple_fields+=("$(trim_whitespace "$current")")
}

load_cinnamon_sources() {
    local raw=""
    local tuple=""
    local index=""
    local current_flag=""
    local i

    raw="$("$GDBUS_CMD" call --session \
        --dest "$DBUS_DEST" \
        --object-path "$DBUS_OBJECT_PATH" \
        --method "$DBUS_INTERFACE.GetInputSources" 2>/dev/null)" || return 1

    extract_source_tuples "$raw"
    if [[ ${#source_tuples[@]} -eq 0 ]]; then
        return 1
    fi

    source_indexes=()
    current_source_pos=-1

    for ((i = 0; i < ${#source_tuples[@]}; i++)); do
        tuple="${source_tuples[i]}"
        split_tuple_fields "$tuple"
        if [[ ${#tuple_fields[@]} -lt 12 ]]; then
            return 1
        fi

        index="$(trim_whitespace "${tuple_fields[2]}")"
        current_flag="$(trim_whitespace "${tuple_fields[11]}")"

        source_indexes+=("$index")
        if [[ "$current_flag" == "true" ]]; then
            current_source_pos=$i
        fi
    done

    [[ $current_source_pos -ge 0 ]]
}

switch_layout_gdbus() {
    local next_pos=0
    local next_index=""

    load_cinnamon_sources || return 1

    next_pos=$(((current_source_pos + 1) % ${#source_indexes[@]}))
    next_index="${source_indexes[next_pos]}"

    "$GDBUS_CMD" call --session \
        --dest "$DBUS_DEST" \
        --object-path "$DBUS_OBJECT_PATH" \
        --method "$DBUS_INTERFACE.ActivateInputSourceIndex" \
        "$next_index" >/dev/null 2>&1
}

switch_layout() {
    if [[ -n "$GDBUS_CMD" ]] && switch_layout_gdbus; then
        return 0
    fi

    if [[ -n "$LAYOUT_SWITCH_CMD" ]]; then
        log_debug "Falling back to cinnamon-xkb-switch helper"
        "$LAYOUT_SWITCH_CMD" -n
        return $?
    fi

    return 1
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
readonly LAYOUT_SWITCH_CMD="$(resolve_layout_switch_cmd 2>/dev/null || true)"
if [[ -z "$GDBUS_CMD" && -z "$LAYOUT_SWITCH_CMD" ]]; then
    echo "Cannot find gdbus or cinnamon-xkb-switch." >&2
    exit 1
fi
readonly KEYBOARD_ID="$(resolve_keyboard_id)" || exit 1
acquire_lock
log_debug "Using config file $CONFIG_FILE"
log_debug "Listening on keyboard id $KEYBOARD_ID"
if [[ -n "$GDBUS_CMD" ]]; then
    log_debug "Using direct gdbus backend: $GDBUS_CMD"
elif [[ -n "$LAYOUT_SWITCH_CMD" ]]; then
    log_debug "Using helper backend: $LAYOUT_SWITCH_CMD"
fi

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
