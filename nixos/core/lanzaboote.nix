# Secure Boot with Lanzaboote + TPM2 auto-unlock
# Import this in hosts that need Secure Boot (currently g5, g6, halo)
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [inputs.lanzaboote.nixosModules.lanzaboote];

  boot = {
    loader.systemd-boot.enable = lib.mkForce false; # Lanzaboote replaces systemd-boot
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
      autoGenerateKeys.enable = true;
      autoEnrollKeys.enable = true;
    };
  };

  # keyring-tpm-unlock.nix also gates on this flag, so turning it off takes
  # keyring auto-unlock with it
  security.tpm2.enable = true;

  environment.systemPackages = with pkgs; [
    sbctl # Secure boot key management
    tpm2-tools # TPM utilities
  ];
}
