{
  inputs,
  config,
  lib,
  ...
}: {
  # secrets/default.nix points non-server hosts at a user key that does not
  # exist at activation time. identityPaths is a list, so a plain assignment
  # would append to that key rather than replace it.
  age.identityPaths = lib.mkForce ["/etc/ssh/ssh_host_ed25519_key"];

  age.secrets = {
    stole_ro_cloudflare_token = {
      file = "${inputs.mysecrets}/stole_ro_cloudflare_token.age";
      owner = config.username;
      mode = "0400";
    };
    nixAccessTokens = {
      file = "${inputs.mysecrets}/personal-nix-access-tokens.age";
      mode = "0440";
      group = "wheel";
    };
  };

  # The secret is env-file shaped (CLOUDFLARE_API_TOKEN=...) and the fish init in
  # home/terminal/fish expands this path into the environment. Symlink mode (the
  # default) preserves the secret's 0400 ownership; copying gives nobody:nogroup.
  environment.etc."agenix/host_env.env".source = config.age.secrets.stole_ro_cloudflare_token.path;
}
