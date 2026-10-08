# Unlike halo, g5 roams onto the work tailnet and tailscale0 is a trusted
# interface, so the proxy binds loopback only and reaches the phone through its
# own Caddy-run node on the personal tailnet, limited to allowedLogins.
{
  config,
  lib,
  ...
}: let
  authKey = config.age.secrets.tp-p14s-factify-agents-ts-authkey or null;
in {
  services.localProxy = {
    enable = true;
    # Not the hostname: it resolves to 127.0.0.2, which nothing binds.
    hostNames = ["localhost" "127.0.0.1"];
    listenAddresses = ["127.0.0.1" "::1"];
    landingPage.enable = true;
    tailscale = {
      enable = true;
      nodeName = "tp-g5-agents";
      tailnetDomain = "tail68e513.ts.net";
      allowedLogins = ["stellern@gmail.com"];
      authKeyFile = lib.mapNullable (s: s.path) authKey;
    };
  };

  warnings = lib.optional (authKey == null) "tp-g5: mysecrets has no tp-p14s-factify-agents-ts-authkey.age, so Caddy's tsnet node tp-g5-agents logs a login URL to `journalctl -u caddy` instead of joining with an auth key.";
}
