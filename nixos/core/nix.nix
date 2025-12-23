{...}: let
  caches = import ../../lib/caches.nix;
in {
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

      # allow sudo users to mark the following values as trusted
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];

      download-buffer-size = 128 * 1024 * 1024; # 128 MiB

      # Use shared cache configuration from lib/caches.nix
      inherit (caches) substituters;
      trusted-public-keys = caches.trustedPublicKeys;
      extra-substituters = caches.extraSubstituters;
      extra-trusted-public-keys = caches.extraTrustedPublicKeys;
    };
  };
}
