# Shared binary cache configuration
# Used by flake.nix (nixConfig, as a literal copy) and, through self.lib.caches,
# by nixos/core/nix.nix (nix.settings) and the installer
let
  # Cloudflare R2 bucket nix-config-cache, served over a custom domain; CI signs uploads with this key (scripts/nix-cache)
  r2 = {
    url = "https://nix-cache.stole.ro";
    publicKey = "nix-config-r2-1:1+Z5eRY6UHUp3dthhOJFtoXXVz378jvZ0hT4TDwNyPU=";
  };
in {
  inherit r2;

  # Primary substituters - always used
  substituters = [
    "https://cache.nixos.org"
    "https://install.determinate.systems"
    "https://vicinae.cachix.org"
    "https://nix-amd-ai.cachix.org"
    "https://wtc.cachix.org"
    "https://noctalia.cachix.org"
    "https://lazytmux.cachix.org"
    "https://dispatcher.cachix.org"
    "https://jovian-nixos.cachix.org"
    # CI pushes this repo's own builds to the R2 cache only (r2 below, .github/workflows/build.yml)
    r2.url
  ];

  # Extra substituters - lower priority
  extraSubstituters = [
    "https://nixpkgs-unfree.cachix.org"
    "https://nix-community.cachix.org"
    "https://yazi.cachix.org"
    # Raspberry Pi kernels; CI also pushes the example-rpi4 closure and kernel headers (dev) to our own cache
    "https://nixos-raspberrypi.cachix.org"

    # llm-agents.nix publishes here, NOT numtide.cachix.org
    "https://cache.numtide.com"
  ];

  # Keys for primary substituters
  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    # install.determinate.systems signs with the FlakeHub keys
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    "wtc.cachix.org-1:rXr2jpSoAtqezDz8xK/gPMjH2Rgyda0zOErfk3N5WnI="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    "lazytmux.cachix.org-1:8P28D3LZAKqPlkEGKzRRU9gon3rgBv4u8/4VWRn6TCg="
    "dispatcher.cachix.org-1:OjkT5jt+C70rFMG3/BfWLlsY25j18cxQo4p4yn23F0A="
    "jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo="
    r2.publicKey
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
