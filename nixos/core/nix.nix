{
  inputs,
  lib,
  ...
}: let
  caches = import ../../lib/caches.nix;
in {
  imports = [
    inputs.determinate.nixosModules.default
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix = {
    # To protect nix-shell agains GC (development env)
    settings = {
      keep-outputs = true;
      keep-derivations = true;

      # Manual optimise storage: nix-store --optimise
      # https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-optimise-store
      auto-optimise-store = true;
      builders-use-substitutes = true;

      # enable flakes globally
      experimental-features = ["nix-command" "flakes"];

      # Trust flake.nix nixConfig (substituters, keys) without prompts
      accept-flake-config = true;

      # allow sudo users to mark the following values as trusted
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];

      download-buffer-size = 128 * 1024 * 1024; # 128 MiB

      # No post-build-hook: FlakeHub Cache only accepts pushes from trusted CI
      # runners, so a laptop has nowhere to push. Use `just seed-host` to share
      # locally-built paths between hosts instead.

      # Use shared cache configuration from lib/caches.nix
      inherit (caches) substituters;
      trusted-public-keys = caches.trustedPublicKeys;
      trusted-substituters = caches.trustedSubstituters;
      extra-substituters = caches.extraSubstituters;
      extra-trusted-public-keys = caches.extraTrustedPublicKeys;

      # All threads per build; the scheduling below keeps the host responsive.
      cores = 0;
    };

    # Not `idle`: that starves builds outright while anything else is busy.
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedClass = "idle";
  };

  systemd.services.nix-daemon.serviceConfig = {
    Nice = 19;
    # Throttles builds before they push the desktop into swap: 30% of a 54 GiB
    # laptop is the ~16 GiB desktop working set measured during a big build.
    MemoryHigh = lib.mkDefault "70%";
  };
}
