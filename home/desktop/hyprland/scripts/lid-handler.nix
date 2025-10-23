{pkgs, ...}: {
  # Hyprland lid event handler - workaround for hyprdynamicmonitors UPower ACAD issue
  # Handles spurious events from external keyboards by checking actual ACPI state
  home.packages = [
    (pkgs.writeShellScriptBin "hyprland-lid-handler" (builtins.readFile ./lid-handler.sh))
  ];
}
