{
  pkgs,
  lib,
  ...
}: let
  volume-control = pkgs.writeShellScriptBin "volume-control" ''
    #!/usr/bin/env bash

    # Simple volume control for NixOS with notifications
    # Usage: volume-control [--get|--inc|--dec|--toggle|--toggle-mic|--get-icon|--mic-inc|--mic-dec]

    iDIR="$HOME/.config/swaync/icons"

    # Get volume percentage
    get_volume() {
        wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
    }

    # Get volume icon
    get_icon() {
        local vol=$(get_volume)
        local muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "MUTED" && echo "true" || echo "false")

        if [[ "$muted" == "true" ]]; then
            echo "$iDIR/volume-mute.png"
        elif [[ "$vol" -le 30 ]]; then
            echo "$iDIR/volume-low.png"
        elif [[ "$vol" -le 60 ]]; then
            echo "$iDIR/volume-mid.png"
        else
            echo "$iDIR/volume-high.png"
        fi
    }

    # Notify user
    notify_volume() {
        local vol=$(get_volume)
        local muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "MUTED" && echo "true" || echo "false")
        local icon=$(get_icon)

        if [[ "$muted" == "true" ]]; then
            notify-send -e -h string:x-canonical-private-synchronous:volume_notif -u low -i "$icon" " Volume: Muted"
        else
            notify-send -e -h int:value:"$vol" -h string:x-canonical-private-synchronous:volume_notif -u low -i "$icon" " Volume: $vol%"
            sounds --volume 2>/dev/null
        fi
    }

    # Mic functions
    get_mic_volume() {
        wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk '{print int($2 * 100)}'
    }

    notify_mic() {
        local vol=$(get_mic_volume)
        local muted=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q "MUTED" && echo "true" || echo "false")
        local icon="$iDIR/microphone.png"

        [[ "$muted" == "true" ]] && icon="$iDIR/microphone-mute.png"

        local msg="$vol%"
        [[ "$muted" == "true" ]] && msg="Muted"

        notify-send -e -h int:value:"$vol" -h string:x-canonical-private-synchronous:volume_notif -u low -i "$icon" "Mic-Level: $msg"
    }

    case "$1" in
        "--get")        get_volume ;;
        "--get-icon")   get_icon ;;
        "--inc")        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ && notify_volume ;;
        "--dec")        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && notify_volume ;;
        "--toggle")     wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && notify_volume ;;
        "--toggle-mic") wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && notify_mic ;;
        "--mic-inc")    wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%+ && notify_mic ;;
        "--mic-dec")    wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%- && notify_mic ;;
        # Legacy support
        "up")           wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ && notify_volume ;;
        "down")         wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && notify_volume ;;
        "mute")         wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && notify_volume ;;
        "mic-mute")     wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && notify_mic ;;
        *)              get_volume ;;
    esac
  '';
in {
  home.packages = [volume-control];
}
