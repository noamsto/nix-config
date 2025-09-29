{pkgs, ...}: let
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


    # Mic functions
    get_mic_volume() {
        wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | awk '{print int($2 * 100)}'
    }


    case "$1" in
        "--get")        get_volume ;;
        "--get-icon")   get_icon ;;
        "--inc")        wpctl set-volume -l 1.25 @DEFAULT_AUDIO_SINK@ 5%+ && sounds --volume 2>/dev/null ;;
        "--dec")        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && sounds --volume 2>/dev/null ;;
        "--toggle")     wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && sounds --volume 2>/dev/null & ;;
        "--toggle-mic") wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
        "--mic-inc")    wpctl set-volume -l 1.25 @DEFAULT_AUDIO_SOURCE@ 5%+ ;;
        "--mic-dec")    wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%- ;;
        *)              get_volume ;;
    esac
  '';
in {
  home.packages = [volume-control];
}
