{lib, ...}: {
  imports = [./palette.nix];

  # Deliberately has no default: each platform wrapper assigns its own
  # derivation, so the Mac closure never pulls the Linux-only deps that the
  # Hyprland theme-toggle needs.
  options.programs.theme-toggle.package = lib.mkOption {
    type = lib.types.package;
    description = "The platform's theme switcher package.";
  };
}
