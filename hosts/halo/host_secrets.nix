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
    # Raw Jellarr API key. Inserted into Jellyfin's database by
    # services.jellyfinHost.declarative on first sync, then used to drive
    # libraries/users/encoding through the REST API.
    jellarr_api_key = {
      file = "${inputs.mysecrets}/jellarr-api-key.age";
      mode = "0400";
    };
    # Plaintext Jellyfin password for the declared `noams` user. Read by the
    # Jellarr service, which runs as `jellyfin`, and only consumed when the
    # user is first created.
    jellyfin_noams_password = {
      file = "${inputs.mysecrets}/jellyfin-noams-password.age";
      owner = "jellyfin";
      mode = "0400";
    };
    # TELEGRAM_BOT_TOKEN=... for Hermes; merged into $HERMES_HOME/.env.
    hermes-env = {
      file = "${inputs.mysecrets}/hermes-env.age";
      owner = "hermes";
      mode = "0400";
    };
    # 1Password service account token (halo-toddl-ro). Keep it out of
    # host_env.env: a global export hands it to every agent session on halo.
    op-sa-toddl = {
      file = "${inputs.mysecrets}/op-sa-toddl.age";
      owner = config.username;
      mode = "0400";
    };
    # 1Password service account for portfolio-agent (read-only on its vault).
    # Only the research runner reads it; hermes must not.
    op-sa-portfolio = {
      file = "${inputs.mysecrets}/op-sa-portfolio.age";
      owner = config.username;
      mode = "0400";
    };
  };

  # The secret is env-file shaped (CLOUDFLARE_API_TOKEN=...) and the fish init in
  # home/terminal/fish expands this path into the environment. Symlink mode (the
  # default) preserves the secret's 0400 ownership; copying gives nobody:nogroup.
  environment.etc."agenix/host_env.env".source = config.age.secrets.stole_ro_cloudflare_token.path;
}
