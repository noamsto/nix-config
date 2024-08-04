{username, ...}: {
  # do garbage collection weekly to keep disk usage low
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # To protect nix-shell agains GC (development env)
  nix.settings = {
    keep-outputs = true;
    keep-derivations = true;
  };

  # Manual optimise storage: nix-store --optimise
  # https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-optimise-store
  nix.settings.auto-optimise-store = true;

  nix.settings.builders-use-substitutes = true;

  # enable flakes globally
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = [username];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
