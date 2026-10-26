# Home Manager configurations
#
# These are aliases onto each host's embedded Home Manager, not standalone
# `homeManagerConfiguration`s.
#
# Every host already wires HM as a NixOS or nix-darwin module with
# `useUserPackages = true` (../home/default.nix, ../hosts/mbp-m4-pro). A second
# standalone evaluation of ../home/profile.nix is therefore a *different* config
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
{
  config,
  inputs,
  ...
}: {
  # Declares typed `flake.homeModules` and `flake.homeConfigurations`.
  imports = [inputs.home-manager.flakeModules.home-manager];

  flake.homeConfigurations = config.flake.lib.homeAliases {
    user = "noams";
    # Default configs for nh auto-detection (username@hostname)
    hosts = {
      inherit (config.flake.nixosConfigurations) tp-g6 halo;
      inherit (config.flake.darwinConfigurations) mbp-m4-pro;
    };
    aliases = {
      # Fallback for nh auto-detection (username only)
      noams = "tp-g6";
      # Legacy name for compatibility
      noams-hyprland = "tp-g6";
    };
  };
}
