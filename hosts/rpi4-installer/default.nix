# Custom WiFi configuration overlay for rpi4-installer
{
  nixos-raspberrypi,
  pkgs,
  ...
}: {
  # Override networking to disable iwd and use wpa_supplicant with pre-hashed PSK
  networking = {
    hostName = "rpi4-installer";

    # Disable iwd (from base config) and use wpa_supplicant
    wireless = {
      enable = true;
      iwd.enable = false; # Override the base config
      networks = {
        "Gal&Noam" = {
          # Pre-hashed PSK for "Gal&Noam"
          pskRaw = "4b9d8676eba84131b06630f8ed035a09f386ffddb5c72104d9d9f3565858483c";
        };
      };
    };
  };

  # Keep SSH access configured
  users.users.nixos.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
  ];
}
