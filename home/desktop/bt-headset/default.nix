{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  bt-headset-mode = pkgs.writeShellApplication {
    name = "bt-headset-mode";
    runtimeInputs = with pkgs; [pipewire wireplumber jq libnotify coreutils];
    text =
      builtins.replaceStrings
      ["@planJq@" "@nodesJq@"]
      ["${./plan.jq}" "${./nodes.jq}"]
      (builtins.readFile ./bt-headset-mode.sh);
  };

  commands = {
    call = "Call Mode";
    music = "Music Mode";
    toggle = "Toggle Mode";
  };

  script = mode: title:
    pkgs.writeScript "headset-${mode}-mode.sh" ''
      #!${pkgs.bash}/bin/bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Headset: ${title}
      # @vicinae.mode silent
      # @vicinae.icon 🎧
      # @vicinae.packageName Bluetooth Headset
      # @vicinae.description Switch the Bluetooth headset (${mode})
      exec ${bt-headset-mode}/bin/bt-headset-mode ${mode}
    '';
in
  lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.packages = [bt-headset-mode];

    # Vicinae discovers script commands under $XDG_DATA_HOME/vicinae/scripts
    # (Omnicast::dataSearchPaths("scripts")); vicinae is only imported on hyprland.
    xdg.dataFile = lib.mkIf (osConfig.desktop.mode == "hyprland") (lib.mapAttrs' (
        mode: title:
          lib.nameValuePair "vicinae/scripts/headset-${mode}-mode.sh" {source = script mode title;}
      )
      commands);
  }
