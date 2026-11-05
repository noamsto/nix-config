# Builds `homeConfigurations` aliases onto hosts' embedded Home Manager:
# `<user>@<host>` for each entry of `hosts` (host name -> NixOS or nix-darwin
# system configuration), plus each `aliases.<name> = "<host>"`.
{lib}: {
  user,
  hosts,
  aliases ? {},
}: let
  # Two consumers read a different attribute off a homeConfigurations entry, so
  # both are exposed: nh builds `<name>.config.home.activationPackage`, while
  # `nix flake show`'s built-in schema insists on a top-level
  # `activationPackage` and fails the whole command without it. A host's
  # `home-manager.users.<user>` is what a standalone config calls `.config`.
  aliasOf = hostName: let
    hm = hosts.${hostName}.config.home-manager.users.${user};
  in {
    activationPackage = hm.home.activationPackage;
    config.home.activationPackage = hm.home.activationPackage;
  };
in
  lib.mapAttrs' (name: _: lib.nameValuePair "${user}@${name}" (aliasOf name)) hosts
  // lib.mapAttrs (_: aliasOf) aliases
