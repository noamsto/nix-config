#!/bin/bash

log_message() {
    logger -t "kanshi-lid-profile" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

get_lid_status() {
    if rg -q open /proc/acpi/button/lid/LID/state; then
        echo "open"
    else
        echo "closed"
    fi
}

get_edp1_status() {
    if hyprctl monitors | rg -q "^Monitor eDP-1"; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

change_profile() {
    current_lid_status=$(get_lid_status)
    current_edp1_status=$(get_edp1_status)

    if { [ "$current_lid_status" = "closed" ] && [ "$current_edp1_status" = "enabled" ]; } ||
        { [ "$current_lid_status" = "open" ] && [ "$current_edp1_status" = "disabled" ]; }; then
        log_message "Status mismatch - Lid: $current_lid_status, eDP-1: $current_edp1_status"

        if [ "$current_lid_status" = "open" ]; then
            log_message "Switching to open-lid-profile"
            monitors=$(hyprctl monitors)
            if echo "$monitors" | grep -q "Samsung Electric Company S27H85x"; then
                kanshictl switch home-docked-lid-open
            elif echo "$monitors" | grep -q "Dell Inc. DELL P2723DE"; then
                kanshictl switch work-docked-lid-open
            else
                kanshictl switch undocked
            fi
            tries=$((tries + 1))
            if ((tries >= 2)); then
                kanshictl reload
                tries=0
            fi
        else
            log_message "Switching to closed-lid-profile"
            monitors=$(hyprctl monitors)
            if echo "$monitors" | grep -q "Samsung Electric Company S27H85x"; then
                kanshictl switch home-docked-lid-close
            elif echo "$monitors" | grep -q "Dell Inc. DELL P2723DE"; then
                kanshictl switch work-docked-lid-close
            else
                kanshictl switch undocked
            fi
            tries=$((tries + 1))
            if ((tries >= 2)); then
                kanshictl reload
                tries=0
            fi
        fi

        previous_lid_status=$current_lid_status
    fi
}

# Initialize previous lid status
previous_lid_status=$(get_lid_status)
tries=0
log_message "Initial status - Lid: $previous_lid_status"

log_message "Starting lid and monitor status monitoring loop"
while true; do
    change_profile
    sleep 2
done
