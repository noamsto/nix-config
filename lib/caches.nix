# Shared binary cache configuration
# Used by flake.nix (nixConfig, as a literal copy) and, through self.lib.caches,
# by nixos/core/nix.nix (nix.settings) and the installer
{
  # Primary substituters - always used
  substituters = [
    "https://cache.nixos.org"
    "https://cache.flakehub.com"
    "https://vicinae.cachix.org"
    "https://nix-amd-ai.cachix.org"
    "https://wtc.cachix.org"
    "https://noctalia.cachix.org"
    "https://lazytmux.cachix.org"
    "https://dispatcher.cachix.org"
    "https://jovian-nixos.cachix.org"
  ];

  # Extra substituters - lower priority
  extraSubstituters = [
    "https://nixpkgs-unfree.cachix.org"
    "https://nix-community.cachix.org"
    "https://yazi.cachix.org"

    # llm-agents.nix publishes here, NOT numtide.cachix.org
    "https://cache.numtide.com"
  ];

  # Keys for primary substituters
  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
    "cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU="
    "cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU="
    "cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8="
    "cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ="
    "cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o="
    "cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y="
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    "wtc.cachix.org-1:rXr2jpSoAtqezDz8xK/gPMjH2Rgyda0zOErfk3N5WnI="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    "lazytmux.cachix.org-1:8P28D3LZAKqPlkEGKzRRU9gon3rgBv4u8/4VWRn6TCg="
    "dispatcher.cachix.org-1:OjkT5jt+C70rFMG3/BfWLlsY25j18cxQo4p4yn23F0A="
    "jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo="
  ];

  # Keys for extra substituters
  extraTrustedPublicKeys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
    "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="

    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];

  # FlakeHub Cache uses JWT auth + public key signing
  trustedSubstituters = ["https://cache.flakehub.com"];
}
