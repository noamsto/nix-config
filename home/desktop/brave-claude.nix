{
  lib,
  pkgs,
  config,
  ...
}: let
  # Over SSH, brave must not run in the login session: it would block the caller
  # and die with it. WAYLAND_DISPLAY can't tell the cases apart (it is a universal
  # fish variable, so SSH shells have it too); the user manager does have the
  # graphical session's environment, so systemd-run starts it there. Brave's
  # singleton hands off to an already-running instance.
  brave-claude = pkgs.writeShellApplication {
    name = "brave-claude";
    runtimeInputs = [pkgs.systemd];
    text = ''
      brave=${lib.getExe config.programs.brave.finalPackage}

      if [ -z "''${SSH_CONNECTION:-}" ] && [ -n "''${WAYLAND_DISPLAY:-}" ]; then
        exec "$brave" "$@"
      fi

      exec systemd-run --user --collect "$brave" "$@"
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.packages = [brave-claude];
  }
