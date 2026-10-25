# System side of priors: the binary and its trust file. Shared with nix-darwin,
# so it uses only options both platforms have (`environment.etc`,
# `environment.systemPackages`, `home-manager.users`).
#
# priors walks the trust file's path and requires every component to be
# root-owned and writable by root only (or sticky, as `/nix/store` is).
# `environment.etc`'s default store symlink meets that on both platforms, so
# the file sets no `mode`.
#
# The binary and the trust file both come from the one hookyard input: priors
# fails closed on a trust key it does not know, so they must not drift apart.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.priors;
  inherit (config.home-manager.users.${config.username}.home) homeDirectory;
in {
  options.priors = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install priors, its trust file and (via home/ai/priors) the personal store.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.hookyard.packages.${pkgs.stdenv.hostPlatform.system}.priors;
      readOnly = true;
    };
    workNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Trust-file `work_names` floor; the user config can only add to it.";
    };
    trustRoot = lib.mkOption {
      type = lib.types.enum ["owner-admin" "separate"];
      default = "owner-admin";
      description = "Trust-file `trust_root`. `separate` turns attestation on, which also needs the priors-verify units this config does not deploy yet.";
    };
    personalStore = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = {
        id = "noamsto-priors-personal";
        path = "${homeDirectory}/memory/personal";
        # Port 443: these hosts reach GitHub ssh only through ssh.github.com:443
        # (home/ssh), and priors' push ignores ~/.ssh/config, so the alias can't be used.
        remote = "ssh://git@ssh.github.com:443/noamsto/priors-personal.git";
      };
      description = "The personal store's trust-file pin; home/ai/priors clones from the same value.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
    environment.etc."priors/trust.toml".source = (pkgs.formats.toml {}).generate "priors-trust.toml" {
      profile = "personal";
      # priors rejects an empty list; this placeholder matches no real org.
      work_orgs = ["example.invalid/none"];
      personal_orgs = ["github.com/noamsto"];
      work_names = cfg.workNames;
      trust_root = cfg.trustRoot;
      stores.personal = cfg.personalStore;
    };
  };
}
