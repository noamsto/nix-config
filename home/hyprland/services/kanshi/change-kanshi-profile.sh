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

change_profile() {
    current_status=$(get_lid_status)

    if [ "$current_status" != "$previous_status" ]; then
        log_message "Lid status changed from $previous_status to $current_status"
        if [ "$current_status" = "open" ]; then
            log_message "Switching to open-lid-profile"
            kanshictl switch home-docked-lid-open || kanshictl switch undocked
        else
            log_message "Switching to closed-lid-profile"
            kanshictl switch home-docked-lid-close
        fi
        previous_status=$current_status
    fi
}

# Initialize previous_status
previous_status=$(get_lid_status)
log_message "Initial lid status: $previous_status"

log_message "Starting lid status monitoring loop"

while true; do
    change_profile
    sleep 2
done
