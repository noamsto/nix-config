# Exported flake outputs (nixosModules, homeModules, overlays)
# A module applied to static args is a fresh value with no `key`, so the module
# system cannot deduplicate it; importing `default` plus a group would declare
# that group's options twice. Every application site, nested ones too, goes
# through `applyKeyed`, which keys the module by its path in the repo. Files
# that don't need `inputs`/`self` are exported as plain paths, which the module
# system already dedupes by path.
{
  inputs,
  lib,
  ...
}: let
  inherit (inputs) self;

  # The key and `_file` go on the module itself rather than on a wrapper
  # importing it: modules are collected breadth-first, so each extra level
  # would reorder list definitions (systemPackages, …) and change drvPaths.
  applyKeyed = p: let
    m = import p pubArgs;
    keyed = mod:
      mod
      // {
        key = "nix-config:${lib.removePrefix (toString ../.) (toString p)}";
        _file = toString p;
      };
  in
    if lib.isFunction m
    then lib.setFunctionArgs (args: keyed (m args)) (lib.functionArgs m)
    else keyed m;
  pubArgs = {inherit inputs self applyKeyed;};
in {
  flake = {
    nixosModules = {
      default = applyKeyed ../nixos;
      options = ../options.nix;
      core = applyKeyed ../nixos/core;
      desktop = ../nixos/desktop;
      hyprland = ../nixos/hyprland;
      laptop = ../nixos/laptop;
      hardware = ../nixos/hardware;
      services = applyKeyed ../nixos/services;
      steam-console = applyKeyed ../nixos/steam-console;
      virtualization = ../nixos/virtualization;
      xremap = applyKeyed ../nixos/xremap;
      overlays = applyKeyed ../overlays;
      lanzaboote = applyKeyed ../nixos/core/lanzaboote.nix;
      udev-hwmon = ../nixos/hardware/udev-hwmon.nix;
      iwd-known-networks = ../nixos/core/iwd-known-networks.nix;
      nice-looking-console = ../nixos/core/nice-looking-console.nix;
      home = applyKeyed ../home;
    };

    # Groups a consumer can import without the profile. `terminal` and
    # `desktop` are left out: they read options declared by ../home/theme.
    homeModules = {
      default = applyKeyed ../home/profile.nix;
      ai = applyKeyed ../home/ai;
      git = ../home/git;
      nvim = ../home/nvim;
      ssh = ../home/ssh;
    };

    # lib/overlays.nix is a list; `nix flake check` wants a single overlay function.
    overlays.default = lib.composeManyExtensions (import ../lib/overlays.nix inputs);
  };
}
