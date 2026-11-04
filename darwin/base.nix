{inputs, ...}: {
  config,
  pkgs,
  ...
}: let
  restartDeterminateDaemon = pkgs.writeShellApplication {
    name = "restart-determinate-daemon";
    runtimeInputs = [pkgs.coreutils];
    text = builtins.readFile ./restart-determinate-daemon.sh;
  };
in {
  imports = [inputs.determinate.darwinModules.default];

  nixpkgs.config.allowUnfree = true;

  # Determinate owns Nix; nix-darwin's nix.* options become inert (by design).
  # Caches go here (not nix.settings, which is inert under Determinate). Only
  # the cross-platform caches are useful on darwin — the Linux-specific ones
  # (hyprland, noctalia, nix-amd-ai, vicinae, yazi) are omitted.
  determinateNix = {
    enable = true;
    customSettings = {
      # An untrusted daemon user has its extra substituters / public keys
      # silently ignored, so the caches below need this to apply.
      trusted-users = [
        "root"
        config.username
      ];
      # Auto-accept flake nixConfig substituters/keys without prompting
      # (mirrors nixos/core/nix.nix). Safe: user is trusted above.
      accept-flake-config = true;
      extra-substituters = [
        "https://install.determinate.systems"
        "https://nix-community.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
        "https://claude-code.cachix.org"
        "https://cache.numtide.com" # llm-agents.nix (amp, claude-code, pi); NOT numtide.cachix.org
        "https://lazytmux.cachix.org" # lazytmux (worktrunk/tmux) — cross-platform
        "https://dispatcher.cachix.org" # dispatcher (crew, dispatch) — cross-platform
      ];
      extra-trusted-public-keys = [
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "lazytmux.cachix.org-1:8P28D3LZAKqPlkEGKzRRU9gon3rgBv4u8/4VWRn6TCg="
        "dispatcher.cachix.org-1:OjkT5jt+C70rFMG3/BfWLlsY25j18cxQo4p4yn23F0A="
      ];
    };
  };

  # The daemon reads nix.custom.conf only at startup, so a switch that changes
  # it leaves the old settings live. postActivation runs after /etc is linked.
  system.activationScripts.postActivation.text = ''
    ${restartDeterminateDaemon}/bin/restart-determinate-daemon /etc/nix/nix.custom.conf /var/db/determinate-daemon-conf.sha256
  '';

  # nix.gc.* is inert under Determinate for the same reason as nix.settings
  # above, and determinate-nixd ships no collector of its own — nothing prunes
  # the store unless it is scheduled here. Runs as root so the system profile's
  # generations go too; launchd coalesces runs missed while asleep to the next
  # wake, unlike cron.
  launchd.daemons.nix-gc = {
    command = "/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 30d";
    serviceConfig = {
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 30;
        }
      ];
      StandardOutPath = "/var/log/nix-gc.log";
      StandardErrorPath = "/var/log/nix-gc.log";
    };
  };

  # Fonts (mirrors nixos/core/locale.nix). NixOS installs these system-wide via
  # fonts.packages; darwin needs its own declaration or terminals can't find
  # "FiraCode Nerd Font". nix-darwin installs these into /Library/Fonts.
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    nerd-fonts.ubuntu
  ];

  # Essential CLI tools. On NixOS these come from nixos/packages.nix
  # (environment.systemPackages, "available system-wide"), which darwin doesn't
  # import — so home/packages.nix omits them and they'd otherwise be missing on
  # darwin. This mirrors the cross-platform core. (TODO: factor into a shared
  # lib/ list imported by both, to prevent drift.)
  environment.systemPackages = with pkgs; [
    ripgrep # rg
    fd
    jq
    bat
    eza
    fastfetch
    onefetch
    nvd
    wget
    # No idb-companion: facebook/idb has cut no release since v1.1.8 (Aug 2022),
    # and that build lists zero targets against iOS 26.3 simulators. Simulator
    # automation goes through home/darwin/xcodebuildmcp.nix instead.
  ];

  # programs.fish.enable wires up system-wide fish (completions, /etc/shells).
  programs.fish.enable = true;
}
