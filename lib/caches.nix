# Shared binary cache configuration
# Used by both flake.nix (nixConfig) and nixos/core/nix.nix (nix.settings)
{
  # Primary substituters - always used
  substituters = [
    "https://cache.nixos.org"
    "https://hyprland.cachix.org"
    "https://vicinae.cachix.org"
    "https://claude-code.cachix.org"
  ];

  # Extra substituters - lower priority
  extraSubstituters = [
    "https://nixpkgs-unfree.cachix.org"
    "https://nix-community.cachix.org"
    "https://yazi.cachix.org"
    "https://nixos-raspberrypi.cachix.org"
    "https://numtide.cachix.org"
  ];

  # Keys for primary substituters
  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
  ];

  # Keys for extra substituters
  extraTrustedPublicKeys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
    "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
}
