# Secure Boot with Lanzaboote + TPM2 auto-unlock
# Import this in hosts that need Secure Boot (currently g5, g6)
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [inputs.lanzaboote.nixosModules.lanzaboote];

  boot = {
    initrd.systemd.enable = true; # Required for TPM unlock
    loader.systemd-boot.enable = lib.mkForce false; # Lanzaboote replaces systemd-boot
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
      autoGenerateKeys.enable = true;
      autoEnrollKeys.enable = true;
    };
  };

  # udev rules putting /dev/tpmrm0 in the tss group, so user services can
  # unseal TPM credentials (e.g. keyring-tpm-unlock) without root
  security.tpm2.enable = true;

  environment.systemPackages = with pkgs; [
    sbctl # Secure boot key management
    tpm2-tools # TPM utilities
  ];
}
