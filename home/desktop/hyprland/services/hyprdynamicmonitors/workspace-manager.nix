{
  pkgs,
  serverMode ? false,
}:
# Create workspace-manager script with proper dependencies
pkgs.writeShellApplication {
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
        if serverMode
        then "1"
        else "0"
      }
    ''
    + builtins.readFile ./scripts/workspace-manager.sh;
}
