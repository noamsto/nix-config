{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# Without a GitHub token nix calls the API anonymously — 60 requests/hour, which
# `nix flake update` blows through on this flake's ~40 `github:` inputs, failing
# with HTTP 403. The NixOS hosts `!include` nix-config.nix.accessTokensFile into
# nix.extraOptions (nixos/core/nix.nix); the Mac can't do that, because
# Determinate owns /etc/nix/nix.conf entirely — nix.custom.conf is generated
# from `determinateNix.customSettings`, which emits only `key = value` lines, so
# an `!include` directive cannot be spliced in.
#
# The user-level nix.conf is the one file left that Determinate doesn't own, so
# the option is included here instead. Unset, it falls back to
# access-tokens.conf, written by hand, mode 0600, and deliberately kept out of
# the store and out of this repo. `!include` (unlike `include`) silently skips a
# missing target, so nix still works before that file exists.
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  xdg.configFile."nix/nix.conf".text = ''
    !include ${
      if osConfig.nix-config.nix.accessTokensFile != null
      then osConfig.nix-config.nix.accessTokensFile
      else "${config.xdg.configHome}/nix/access-tokens.conf"
    }
  '';
}
