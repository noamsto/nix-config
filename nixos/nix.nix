{username, ...}: {
  # do garbage collection weekly to keep disk usage low

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

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

      substituters = [
        # replace official cache with a mirror located in China
        "https://mirrors.ustc.edu.cn/nix-channels/store"
        "https://cache.nixos.org"
      ];

      # nix community's cache server
      extra-substituters = [
        "https://nixpkgs-unfree.cachix.org"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
      ];
      extra-trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      ];
    };
  };
}
