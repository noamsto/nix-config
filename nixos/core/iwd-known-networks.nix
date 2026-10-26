# Seed iwd's known-network store from the declarative credential set.
#
# NetworkManager's `ensureProfiles` cannot carry these credentials on hosts
# using the iwd backend (the repo default): NM forwards a profile's `psk` to
# iwd as a *passphrase*, so a precomputed 64-hex PMK gets run through PBKDF2 a
# second time and authentication fails. iwd wants the PMK in its own store
# instead, which is where it keeps one anyway.
{
  lib,
  pkgs,
  config,
  ...
}: let
  credentials = config.nix-config.wifi.knownNetworksFile;
in {
  options.nix-config.wifi.knownNetworksFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "JSON list of `{ssid, psk}` objects seeded into iwd's known-network store. Read from the Nix store at boot; null seeds nothing.";
  };

  config = lib.mkIf (config.networking.wireless.iwd.enable && credentials != null) {
    systemd.services.iwd-seed-networks = {
      description = "Seed iwd known networks from mysecrets";
      wantedBy = ["multi-user.target"];
      # iwd reads this directory at startup, so it has to be populated first.
      before = ["iwd.service"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m700 -o root -g root /var/lib/iwd

        ${pkgs.jq}/bin/jq -r '.[] | [.ssid, .psk] | @tsv' ${credentials} \
        | while IFS="$(printf '\t')" read -r ssid psk; do
            # iwd escapes any SSID that is not filename-safe as "=<hex>"; the
            # escaped form is always accepted, so use it unconditionally rather
            # than reimplementing iwd's is-this-safe test.
            hex=$(printf '%s' "$ssid" | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n')
            target="/var/lib/iwd/=$hex.psk"

            # Seed only. Once iwd owns the file it may add its own state
            # (last-connected, frequencies); clobbering that on every boot
            # would throw away roaming hints.
            [ -e "$target" ] && continue

            printf '[Security]\nPreSharedKey=%s\n' "$psk" > "$target"
            chmod 600 "$target"
          done
      '';
    };
  };
}
