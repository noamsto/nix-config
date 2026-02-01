{
  inputs,
  config,
  ...
}: {
  age.secrets = {
    # thinkpad_p14s_ssh.file = "${inputs.mysecrets}/thinkpad_p14s_ssh.age";
    # thinkpad_p14s_aliases.file = "${inputs.mysecrets}/thinkpad_p14s_aliases.age";
    tp-p14s-env.file = "${inputs.mysecrets}/tp-p14s-env.age";
    nixAccessTokens = {
      file = "${inputs.mysecrets}/tp-p14s-nix-access-tokens.age";
      mode = "0440";
      group = "wheel";
    };
    noams_flakehub = {
      file = "${inputs.mysecrets}/noams_flakehub.age";
      owner = config.username;
      mode = "0400";
    };
  };

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  environment.etc = {
    "agenix/host_env.env" = {
      source = config.age.secrets.tp-p14s-env.path;
      mode = "0644";
    };
  };
}
