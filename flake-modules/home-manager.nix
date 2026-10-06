# Home Manager configurations
#
# These are aliases onto each host's embedded Home Manager, not standalone
# `homeManagerConfiguration`s.
#
# Every host already wires HM as a NixOS or nix-darwin module with
# `useUserPackages = true` (../home/default.nix, ../hosts/mbp-m4-pro). A second
# standalone evaluation of ../home/noams.nix is therefore a *different* config
# that fights the embedded one over `~/.nix-profile`: standalone activation
# installs `home-manager-path` there, embedded activation uninstalls it, so
# `home.profileDirectory` follows whichever command ran last. Anything that
# bakes that path — hookyard's router, the Claude Code hook overlay — then
# names a profile that may be empty, and its hooks die with exit 127.
#
# Aliasing keeps one evaluation per host. `nh home switch .` builds
# `homeConfigurations.<name>.config.home.activationPackage` (nh 4.4.2,
# crates/nh-home/src/home.rs:269), which is the shape produced below; `just hm`
# reaches the same derivation without going through nh.
#
# Packages are deliberately not installed by this path. They live in the system
# profile, so adding or removing one needs `nh os switch` / `nh darwin switch`.
{config, ...}: let
  # Two consumers read a different attribute off a homeConfigurations entry, so
  # both are exposed: nh builds `<name>.config.home.activationPackage`, while
  # `nix flake show`'s built-in schema insists on a top-level
  # `activationPackage` and fails the whole command without it. A host's
  # `home-manager.users.noams` is what a standalone config calls `.config`.
  aliasOf = hmConfig: {
    activationPackage = hmConfig.home.activationPackage;
    config.home.activationPackage = hmConfig.home.activationPackage;
  };

  nixosHome = hostName:
    aliasOf config.flake.nixosConfigurations.${hostName}.config.home-manager.users.noams;

  darwinHome = hostName:
    aliasOf config.flake.darwinConfigurations.${hostName}.config.home-manager.users.noams;
in {
  flake.homeConfigurations = {
    # Default configs for nh auto-detection (username@hostname)
    "noams@tp-g5" = nixosHome "tp-g5";
    "noams@tp-g6" = nixosHome "tp-g6";
    "noams@halo" = nixosHome "halo";
    "noams@mbp-m4-pro" = darwinHome "mbp-m4-pro";

    # Fallback for nh auto-detection (username only, defaults to personal)
    noams = nixosHome "tp-g6";

    # Legacy names for compatibility
    noams-hyprland = nixosHome "tp-g6";
    noams-hyprland-work = nixosHome "tp-g5";
  };
}
