# Exported flake outputs (nixosModules, overlays)
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
  # flake-parts' nixosModules option wraps every value in extra module levels;
  # modules are collected breadth-first, so hosts importing through it would
  # reorder list definitions and change their drvPaths. Undeclared, the
  # exports pass through as plain values, without its `_class` check, and
  # `flake.nixosModules` falls back to the freeform `flake` type, which takes
  # one definition: every entry has to be defined in this file.
  disabledModules = ["${inputs.flake-parts}/modules/nixosModules.nix"];

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
    };

    # lib/overlays.nix is a list; `nix flake check` wants a single overlay function.
    overlays.default = lib.composeManyExtensions (import ../lib/overlays.nix inputs);
  };
}
