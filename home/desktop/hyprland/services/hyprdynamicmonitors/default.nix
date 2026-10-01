{
  inputs,
  pkgs,
  lib,
  osConfig,
  ...
}: let
  # Create workspace-manager script with proper dependencies
  workspaceManager = pkgs.writeShellApplication {
    name = "workspace-manager";
    runtimeInputs = [
      pkgs.glib # provides gdbus for lid state checking
      pkgs.procps # provides pgrep for the noctalia liveness probe
      (import ../../scripts/xresources-apply.nix {inherit pkgs;}) # Xft.dpi profile apply/record
    ];
    # In server mode the box stays awake with the lid closed — skip the
    # undocked-lid-closed suspend handler (mirrors the system-awake guard).
    text =
      ''
        readonly SERVER_MODE=${
          if osConfig.machine.serverMode or false
          then "1"
          else "0"
        }
      ''
      + builtins.readFile ./scripts/workspace-manager.sh;
  };

  # Get laptop scale from host config (defaults to 1.25)
  laptopScale = osConfig.laptop-scale or "1.25";

  # Generate profile files with scale substituted
  profilesDir = pkgs.stdenvNoCC.mkDerivation {
    name = "hyprdynamicmonitors-profiles";
    src = ./profiles;
    buildPhase = ''
      mkdir -p $out
      # Process template files (.lua.in -> .lua)
      for file in $src/*.lua.in; do
        if [ -f "$file" ]; then
          filename=$(basename "$file")
          output="$out/''${filename%.in}"
          sed -e "s/@laptopScale@/${laptopScale}/g" "$file" > "$output"
        fi
      done
    '';
    preferLocalBuild = true;
  };

  # Use config.toml directly (workspace-manager is in PATH, no substitutions needed)
  configFile = ./config.toml;
in {
  imports = [inputs.hyprdynamicmonitors.homeManagerModules.default];

  # Configure hyprdynamicmonitors with systemd integration
  home.hyprdynamicmonitors = {
    inherit configFile;
    enable = true;
    extraFlags = ["--enable-lid-events"];
  };

  # Deploy profiles
  xdg.configFile = {
    "hyprdynamicmonitors/profiles".source = profilesDir;
  };

  # Add scripts to PATH
  home.packages = [workspaceManager];

  # Add upower to hyprdynamicmonitors-prepare PATH to fix "upower not found" warning
  systemd.user.services.hyprdynamicmonitors-prepare.Service.Environment = [
    "PATH=${lib.makeBinPath [pkgs.upower]}:$PATH"
  ];

  # NOTE: HDM restart on resume is handled by the system-level service in
  # nixos/laptop/suspend-handling.nix (hyprdynamicmonitors-resume).
  # That service also handles phantom monitor cleanup, eDP-1 enable, and DPMS.
  # Having a duplicate user-level service caused race conditions.
}
