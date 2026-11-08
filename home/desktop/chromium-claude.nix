{
  lib,
  pkgs,
  config,
  ...
}: let
  # Over SSH, Chromium must not run in the login session: it would block the caller
  # and die with it. WAYLAND_DISPLAY can't tell the cases apart (it is a universal
  # fish variable, so SSH shells have it too); the user manager does have the
  # graphical session's environment, so systemd-run starts it there. Chromium's
  # singleton hands off to an already-running instance.
  chromium-claude = pkgs.writeShellApplication {
    name = "chromium-claude";
    runtimeInputs = [pkgs.systemd];
    text = ''
      chromium=${lib.getExe config.programs.chromium.finalPackage}

      if [ -z "''${SSH_CONNECTION:-}" ] && [ -n "''${WAYLAND_DISPLAY:-}" ]; then
        exec "$chromium" "$@"
      fi

      exec systemd-run --user --collect "$chromium" "$@"
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.packages = [chromium-claude];
  }
