# Generic headless Raspberry Pi base: board support from nixos-raspberrypi, a
# wheel user with SSH keys, nix settings and DHCP networking.
#
# The system must be built with `nixos-raspberrypi.lib.nixosSystem`: the board
# modules read its `nixos-raspberrypi` specialArg. `nixosModules.core` is not
# imported (it is desktop-shaped), so the small user, network and nix parts
# below deliberately mirror nixos/core with the same option conventions.
{
  inputs,
  self,
  ...
}: {
  config,
  lib,
  ...
}: let
  inherit (self.lib) caches;
  inherit (config.nix-config) rpi;
in {
  # Imports never depend on `config`. `nix-config.rpi.board` is an enum with a
  # single value for now; a new board is a new enum value plus its own static
  # import here.
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    self.nixosModules.options
    self.nixosModules.nice-looking-console
  ];

  # Reading both options is what makes a missing value an evaluation error: an
  # option nothing reads is never forced.
  assertions = [
    {
      assertion = rpi.board == "rpi4";
      message = "nixosModules.rpi currently imports only raspberry-pi-4.base";
    }
    {
      assertion = rpi.sshAuthorizedKeys != [];
      message = "nix-config.rpi.sshAuthorizedKeys is empty; sshd is key-only, so the host would be unreachable";
    }
  ];

  users.users.${config.username} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = rpi.sshAuthorizedKeys;
    inherit (config.nix-config.user) hashedPasswordFile;
  };

  # Without a password file the user has no password at all, so sudo could never
  # succeed; passwordless sudo for wheel is then the only way to administer the
  # host. Set nix-config.user.hashedPasswordFile to require a password again.
  security.sudo.wheelNeedsPassword = config.nix-config.user.hashedPasswordFile != null;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["@wheel"];
    inherit (caches) substituters;
    trusted-public-keys = caches.trustedPublicKeys;
    extra-substituters = caches.extraSubstituters;
    extra-trusted-public-keys = caches.extraTrustedPublicKeys;
  };

  networking = {
    hostName = config.hostname;
    useDHCP = lib.mkDefault true;
  };

  # Headless: the serial and HDMI consoles are enough, no graphical session.
  desktop.mode = lib.mkDefault "none";
}
