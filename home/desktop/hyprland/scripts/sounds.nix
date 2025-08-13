{
  pkgs,
  lib,
  ...
}: let
  sounds = pkgs.writeShellScriptBin "sounds" ''
    #!/usr/bin/env bash

    # Simple system sounds for NixOS
    # Usage: sounds [--screenshot|--volume]

    case "$1" in
      "--screenshot")
        sound_pattern="screen-capture.*"
        ;;
      "--volume")
        sound_pattern="audio-volume-change.*"
        ;;
      *)
        exit 0
        ;;
    esac

    # Find and play sound from freedesktop theme
    sound_dir="${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo"
    sound_file=$(find "$sound_dir" -name "$sound_pattern" -print -quit 2>/dev/null)

    # Play sound if found (PipeWire is guaranteed to be available)
    [[ -f "$sound_file" ]] && pw-play "$sound_file" 2>/dev/null &
  '';
in {
  home.packages = [sounds];
}
