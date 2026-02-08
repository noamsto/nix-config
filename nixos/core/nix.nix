{
  pkgs,
  inputs,
  ...
}: let
  caches = import ../../lib/caches.nix;

  # Post-build hook to push to FlakeHub Cache
  # Only runs if auth exists, never fails the build
  flakehubPushHook = pkgs.writeShellScript "flakehub-push-hook" ''
    set -f  # disable globbing
    AUTH_FILE="''${HOME:-/root}/.config/flakehub/auth"
    if [ -f "$AUTH_FILE" ] || [ -L "$AUTH_FILE" ]; then
      ${pkgs.fh}/bin/fh cache push $OUT_PATHS >/dev/null 2>&1 || true
    fi
    exit 0
  '';
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

      # Push builds to FlakeHub Cache (if authenticated)
      post-build-hook = flakehubPushHook;

      # Use shared cache configuration from lib/caches.nix
      inherit (caches) substituters;
      trusted-public-keys = caches.trustedPublicKeys;
      trusted-substituters = caches.trustedSubstituters;
      extra-substituters = caches.extraSubstituters;
      extra-trusted-public-keys = caches.extraTrustedPublicKeys;
    };
  };
}
