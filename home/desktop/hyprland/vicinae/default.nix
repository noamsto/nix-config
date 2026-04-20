{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (inputs.vicinae.packages.${pkgs.system}) mkVicinaeExtension mkRayCastExtension;

  # Vicinaehq monorepo: already pinned via `vicinae-extensions` flake input.
  # Each subdir has its own package-lock.json, so mkVicinaeExtension builds it cleanly.
  mkVicinaeHqExt = name:
    mkVicinaeExtension {
      pname = "vicinae-ext-${name}";
      version = "unstable-${inputs.vicinae-extensions.shortRev or "dirty"}";
      src = inputs.vicinae-extensions + "/extensions/${name}";
    };

  # Raycast monorepo is ~15GB, so we sparse-checkout only the extensions we use.
  # `names`, `rev`, and `hash` all live in raycast-sources.nix — edit names there,
  # then run `just update-vicinae-extensions` to refresh rev/hash.
  raycastSources = import ./raycast-sources.nix;
  raycastSrc = pkgs.fetchFromGitHub {
    owner = "raycast";
    repo = "extensions";
    inherit (raycastSources) rev hash;
    sparseCheckout = map (n: "extensions/${n}") raycastSources.names;
  };
  mkRaycastExt = name:
    mkRayCastExtension {
      inherit name;
      src = raycastSrc + "/extensions/${name}";
      # Electron's postinstall tries to download a prebuilt binary over the network,
      # which the Nix sandbox blocks. Raycast extensions don't use electron at
      # runtime — skip the download.
      env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    };

  vicinaeHqExtensionNames = [
    "bluetooth"
    "firefox"
    "hypr-keybinds"
    "it-tools"
    "nix"
    "port-killer"
    "process-manager"
    # "systemd" — disabled: pulls usocket which pins node-gyp@7 and fails to build
    # against Node 24. Install imperatively via the vicinae store if needed.
    "wifi-commander"
  ];
in {
  imports = [
    inputs.vicinae.homeManagerModules.default
  ];
  home.packages = with pkgs; [
    libqalculate
  ];
  services.vicinae = {
    enable = true;
    systemd = {
      enable = true;
      autoStart = true;
    };
    extensions =
      map mkVicinaeHqExt vicinaeHqExtensionNames
      ++ map mkRaycastExt raycastSources.names;
  };

  # Seed vicinae config only if it doesn't exist yet; vicinae manages it at runtime
  home.activation.seedVicinaeConfig = let
    seedConfig = pkgs.writeText "vicinae-seed-config.json" (builtins.toJSON {
      "$schema" = "https://vicinae.com/schemas/config.json";
      keybinding = "default";
      theme.dark.name = "vicinae-dark";
      keybinds = {};
      providers = {
        applications.preferences.paths = [
          "${config.home.homeDirectory}/.local/share/applications"
          "/var/lib/flatpak/exports/share/applications"
          "/etc/profiles/per-user/${config.home.username}/share/applications"
          "/run/current-system/sw/share/applications"
        ];
        clipboard.preferences.monitoring = true;
      };
    });
  in
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      config_path="${config.xdg.configHome}/vicinae/settings.json"
      if [ ! -f "$config_path" ]; then
        mkdir -p "$(dirname "$config_path")"
        cp ${seedConfig} "$config_path"
        chmod 644 "$config_path"
      fi
    '';
}
