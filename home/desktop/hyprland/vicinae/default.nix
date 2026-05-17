{
  inputs,
  config,
  osConfig,
  pkgs,
  lib,
  ...
}: let
  # Keep the launcher's physical-pixel footprint constant across hosts so it
  # looks the same size regardless of Hyprland scale. Reference is g5 at
  # scale=2.0 → 1000×625 logical = 2000×1250 physical.
  scale = builtins.fromJSON (osConfig.laptop-scale or "1.25");
  launcherWidth = builtins.floor (2000.0 / scale);
  launcherHeight = builtins.floor (1250.0 / scale);
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
    # Extensions are installed imperatively via the launcher's Store command.
    # Building from source in the Nix sandbox kept breaking because upstream
    # extension tsconfigs use `extends: "../../tsconfig.json"`, which can't
    # resolve once only the leaf dir is in the sandbox — esbuild then falls
    # back to classic JSX and emits `React.createElement(...)` with no `React`
    # in scope. If a specific extension MUST be reproducible/pinned, add it
    # back here using `inputs.vicinae.packages.${pkgs.system}.mkVicinaeExtension`.
  };

  # Upstream HM module hardcodes KillMode=process: stop only kills the main
  # binary, orphaning the node extension-manager in the cgroup (observed 7.6G
  # held). Mixed mode terminates the whole cgroup cleanly.
  systemd.user.services.vicinae.Service.KillMode = lib.mkForce "mixed";

  home.activation = let
    seedConfig = pkgs.writeText "vicinae-seed-config.json" (builtins.toJSON {
      "$schema" = "https://vicinae.com/schemas/config.json";
      keybinding = "default";
      theme.dark.name = "vicinae-dark";
      keybinds = {};
      launcher_window = {
        opacity = 0.85;
        size = {
          width = launcherWidth;
          height = launcherHeight;
        };
      };
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
  in {
    # nh home switch sometimes stops vicinae (PartOf=graphical-session.target)
    # without restarting it, leaving the launcher dead until next reboot.
    ensureVicinaeRunning = lib.hm.dag.entryAfter ["reloadSystemd"] ''
      if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet vicinae.service; then
        ${pkgs.systemd}/bin/systemctl --user start vicinae.service || true
      fi
    '';

    # Seed vicinae config only if it doesn't exist yet; vicinae manages it at runtime
    seedVicinaeConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      config_path="${config.xdg.configHome}/vicinae/settings.json"
      if [ ! -f "$config_path" ]; then
        mkdir -p "$(dirname "$config_path")"
        cp ${seedConfig} "$config_path"
        chmod 644 "$config_path"
      fi
    '';
  };
}
