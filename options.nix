{
  config,
  lib,
  pkgs,
  ...
}: {
  options = {
    desktop = {
      mode = lib.mkOption {
        type = lib.types.enum ["none" "hyprland"];
        default = "none";
        description = "Desktop mode";
      };
      isEnabled = lib.mkOption {
        type = lib.types.bool;
        default = config.desktop.mode != "none";
        readOnly = true;
      };
      isHyprland = lib.mkOption {
        type = lib.types.bool;
        default = config.desktop.mode == "hyprland";
        readOnly = true;
      };
    };
    # Deliberately NOT a `desktop.mode` value. `desktop.mode` governs whether
    # *this user* gets a desktop and drives the `home/desktop` import in
    # home/profile.nix; the console session runs as a separate account, so none of
    # that should change. Orthogonal axis, not a fourth enum member.
    steamConsole = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run Steam Gaming Mode (Jovian) as a dedicated console user.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "steam";
        description = ''
          Unprivileged account the console session runs as. Deliberately not
          `username`: autologin means whoever holds the TV remote is logged in,
          and that must not be the account with SSH keys, sudo and agent access.
        '';
      };
      start = lib.mkOption {
        type = lib.types.enum ["boot" "manual" "controller"];
        default = "boot";
        description = ''
          How Gaming Mode's display manager gets started:
          - `boot`: started at boot, as usual.
          - `manual`: installed but not booted; start it from the couch or
            over ssh with `systemctl start display-manager`.
          - `controller`: like `manual`, plus a controller Home-button press
            starts it, and Steam's own idle sleep or the TV going off stops
            it. Never stops while a game is running.
        '';
      };
    };
    machine = {
      type = lib.mkOption {
        type = lib.types.enum ["server" "desktop" "laptop"];
        default = "server";
        description = "Machine type";
      };
      isLaptop = lib.mkOption {
        type = lib.types.bool;
        default = config.machine.type == "laptop";
        readOnly = true;
      };
      isPC = lib.mkOption {
        type = lib.types.bool;
        default = config.machine.type == "laptop" || config.machine.type == "desktop";
        readOnly = true;
      };
      serverMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run this host as an always-on headless server: disable autonomous
          suspend (lid-close fallback timer and idle suspend) so SSH/tmux
          sessions survive a closed lid. Thermal emergency suspend stays active.
          Flip back to false to restore normal laptop power behavior.
        '';
      };
    };
    agentDashboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run houston and `hookyard serve` as user services and register them on `services.localProxy`.";
      };
    };
    username = lib.mkOption {
      type = lib.types.str;
      default = "user";
    };
    user-full-name = lib.mkOption {
      type = lib.types.str;
      default = "Example User";
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "user@example.com";
    };
    hostname = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };
    laptop-scale = lib.mkOption {
      type = lib.types.str;
      default = "1.25";
      description = "Laptop display scale";
    };
    flakePath = lib.mkOption {
      type = lib.types.str;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin
        then "/Users/${config.username}/nix-config"
        else "/home/${config.username}/nix-config";
    };
    nix-config = {
      ai = {
        localServer.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether this host runs the local model server: pi defaults to it, and the remote client CLI for it is not installed.";
        };
        dispatcher.localModels = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Local model definitions passed verbatim to programs.dispatcher.localModels.";
        };
        pi.modelsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "File linked as ~/.pi/agent/models.json; null links nothing.";
        };
      };
      terminal.remoteHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "SSH aliases the tmux session picker bridges into.";
      };
      desktop = {
        easyeffects.preset = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum ["thinkpad-p14s-g4-linux" "thinkpad-p14s-g5-linux"]);
          default = null;
          description = "Bundled ThinkPad EasyEffects preset set to install; null installs none.";
        };
        dataMount = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether this host mounts ~/Data, which adds a GTK bookmark for it.";
        };
        avatar = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Image linked as ~/.face; null links nothing.";
        };
        monitors.configFile = lib.mkOption {
          type = lib.types.path;
          default = ./home/desktop/hyprland/services/hyprdynamicmonitors/config.toml;
          defaultText = lib.literalExpression "./home/desktop/hyprland/services/hyprdynamicmonitors/config.toml";
          description = "The hyprdynamicmonitors config.toml.";
        };
      };
      hardware.thinkpad.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to apply the shared ThinkPad boot and hardware settings in nixos/hardware/thinkpad-common.nix.";
      };
      user.hashedPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "File holding the user's hashed password, read at activation; null sets none.";
      };
      nix.accessTokensFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "nix.conf fragment carrying `access-tokens`, `!include`d into the Nix configuration; null includes nothing (on darwin, null keeps the hand-written ~/.config/nix/access-tokens.conf).";
      };
      shell.hostEnvFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "KEY=value file that interactive fish exports when it exists; null skips it.";
      };
    };
  };
}
