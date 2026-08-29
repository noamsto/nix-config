{
  config,
  lib,
  pkgs,
  ...
}:
# Without a GitHub token nix calls the API anonymously — 60 requests/hour, which
# `nix flake update` blows through on this flake's ~40 `github:` inputs, failing
# with HTTP 403. The NixOS hosts get a token by `!include`-ing an agenix path
# into nix.extraOptions (secrets/default.nix); the Mac can't reuse that. It is
# not an agenix recipient, and Determinate owns /etc/nix/nix.conf entirely —
# nix.custom.conf is generated from `determinateNix.customSettings`, which emits
# only `key = value` lines, so an `!include` directive cannot be spliced in.
#
# The user-level nix.conf is the one file left that Determinate doesn't own.
# `!include` (unlike `include`) silently skips a missing target, so nix still
# works before access-tokens.conf exists. That file is written by hand, mode
# 0600, and deliberately stays out of the store and out of this repo.
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  xdg.configFile."nix/nix.conf".text = ''
    !include ${config.xdg.configHome}/nix/access-tokens.conf
  '';
}
