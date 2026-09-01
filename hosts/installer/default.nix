# Generic installer ISO. Boots, joins wifi unattended, exposes sshd — the real
# install is driven from another machine with nixos-anywhere. Deliberately does
# not import nixos/default.nix: the desktop/laptop module tree is irrelevant
# here and would bloat the image.
{
  lib,
  pkgs,
  modulesPath,
  inputs,
  ...
}: let
  hostConfigs = import ../../lib/host-configs.nix;
  caches = import ../../lib/caches.nix;

  # mysecrets is `flake = false`, so its contents are readable at eval time.
  # agenix cannot serve this: it decrypts at activation, which would mean
  # shipping a decryption key inside the image it is meant to protect.
  networks = builtins.fromJSON (builtins.readFile "${inputs.mysecrets}/installer-wifi.json");

  # Keyed by index rather than SSID so the generated
  # /run/NetworkManager/system-connections/<key>.nmconnection filename stays
  # safe regardless of spaces or slashes in the SSID.
  #
  # These profiles carry no credential; they only tell NetworkManager which
  # networks to autoconnect. iwd holds the keys.
  mkWifiProfile = i: net: {
    name = "wifi-${toString i}";
    value = {
      connection = {
        id = net.ssid;
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        inherit (net) ssid;
        mode = "infrastructure";
      };
      # The key itself lives in iwd's store (nixos/core/iwd-known-networks.nix),
      # because NM forwards a profile `psk` to iwd as a *passphrase* and would
      # PBKDF2 the PMK a second time. psk-flags=4 is
      # NM_SETTING_SECRET_FLAG_NOT_REQUIRED: it marks the profile as complete
      # without a secret, rather than merely missing one.
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk-flags = 4;
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../../nixos/core/nice-looking-console.nix
    ../../nixos/core/iwd-known-networks.nix
  ];

  # Real hosts pick this up from their generated hardware-configuration.nix;
  # the installer has none, and mkSystem doesn't pass a `system` arg.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking = {
    hostName = "installer";

    # Match every real host in this repo. The installer previously used the
    # nixpkgs default (wpa_supplicant), and that divergence is what let a
    # credential work here and fail after install: the two backends consume a
    # PSK differently. An installer that does not match the systems it installs
    # cannot catch this class of bug.
    networkmanager = {
      wifi.backend = "iwd";
      ensureProfiles.profiles =
        builtins.listToAttrs (lib.imap0 mkWifiProfile networks);
    };
    wireless.iwd.enable = true;
  };

  # installation-device.nix leaves root with an empty password, which sshd
  # refuses. The authorized key is the only usable way in for nixos-anywhere.
  users.users.root.openssh.authorizedKeys.keys = [hostConfigs.sshPublicKeys.noams];

  nix.settings = {
    # cache.flakehub.com is omitted deliberately: it uses JWT auth the
    # installer has no credentials for, so every fetch would warn for nothing.
    substituters = lib.filter (s: s != "https://cache.flakehub.com") caches.substituters;
    trusted-public-keys = caches.trustedPublicKeys;
    extra-substituters = caches.extraSubstituters;
    extra-trusted-public-keys = caches.extraTrustedPublicKeys;
  };

  # nice-looking-console.nix picks ter-u16n; bump it for HiDPI panels.
  console.font = "${pkgs.terminus_font}/share/consolefonts/ter-u22n.psf.gz";

  # helpLine is types.lines, so a plain definition would append to the stock
  # installer text ("To set up a wireless connection, run nmtui") rather than
  # replace it — hence mkForce.
  #
  # This deliberately does NOT use agetty's \4 escape. agetty renders the issue
  # once, when it draws the prompt — which happens before NetworkManager has
  # associated, so \4 falls back to 127.0.0.1. `agetty --reload` cannot repair
  # it either: it only redraws for an agetty where login has not commenced, and
  # this profile autologins immediately. The address is announced by
  # announce-address.service below instead, once it is actually true.
  services.getty.helpLine = lib.mkForce ''

    Wifi connects automatically. This machine's address is printed below
    as soon as it associates.

    Then, from the nix-config checkout on your laptop:
        just install-host <host> <that address>
  '';

  systemd.services.announce-address = {
    description = "Announce this machine's address on the console once the network is up";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    # getty@tty1 has TTYVTDisallocate=yes and is ordered only after
    # getty-pre.target, so it clears the VT whenever it happens to start. On
    # fast links (QEMU slirp) network-online.target is reached at about the
    # same moment, and getty wipes this message. Ordering after getty too
    # removes the race; on a real wifi link getty is long since up anyway.
    after = ["network-online.target" "getty@tty1.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      addr=$(${pkgs.iproute2}/bin/ip -4 -oneline addr show scope global \
        | ${pkgs.gawk}/bin/awk '{print $4}' \
        | ${pkgs.coreutils}/bin/cut -d/ -f1 \
        | ${pkgs.coreutils}/bin/head -1)
      {
        echo ""
        echo "  Installer is reachable at ''${addr:-<no address yet>}"
        echo "  From your laptop:  just install-host <host> ''${addr:-<address>}"
        echo ""
      } | ${pkgs.coreutils}/bin/tee /dev/tty1
    '';
  };
}
