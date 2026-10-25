{
  lib,
  pkgs,
  ...
}: {
  programs.ssh.settings =
    {
      "naspi.local" = {
        User = "noams";
        IdentityFile = "~/.ssh/id_ed25519";
        ForwardAgent = true;
      };

      # The Mac. Bare tailnet name via MagicDNS (works from any network,
      # same as tp-g6); a Match block falls back to mDNS when the tailnet
      # profile is switched and the name no longer resolves. First HostName
      # wins in ssh_config, so the fallback is dag-ordered BEFORE this block.
      "mbp" = {
        HostName = "mbp-m4-pro";
        User = "noams";
        IdentityFile = "~/.ssh/id_ed25519";
      };

      # g6 (headless server). Tailnet and mDNS names match the hostname —
      # same Match fallback pattern as mbp.
      "tp-g6" = {
        User = "noams";
        IdentityFile = "~/.ssh/id_ed25519";
      };
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      # getent fails when MagicDNS can't resolve the name (tailnet profile
      # switched / tailscale down) — only then does .local take over.
      # Linux-only: macOS has no getent, which would make the exec misfire.
      "Match host mbp exec \"! getent hosts mbp-m4-pro\"" = lib.hm.dag.entryBefore ["mbp"] {
        HostName = "mbp-m4-pro.local";
      };
      "Match host tp-g6 exec \"! getent hosts tp-g6\"" = lib.hm.dag.entryBefore ["tp-g6"] {
        HostName = "tp-g6.local";
      };
    };
}
