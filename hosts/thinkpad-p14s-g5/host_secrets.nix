#NOTE: This File is just for reference on how to add Host specific secrets (Work for example)
{
  config,
  inputs,
  ...
}: {
  age.secrets = {
    tp-p14s-factify-ssh = {
      file = "${inputs.mysecrets}/tp-p14s-factify-ssh.age";
      owner = config.username;
      mode = "0600";
    };
    tp-p14s-factify-env = {
      file = "${inputs.mysecrets}/tp-p14s-factify-env.age";
      owner = config.username;
      mode = "0600";
    };
    nixAccessTokens = {
      file = "${inputs.mysecrets}/tp-p14s-factify-nix-access-tokens.age";
      mode = "0440";
      group = "wheel";
    };
    noams_flakehub = {
      file = "${inputs.mysecrets}/noams_flakehub.age";
      owner = config.username;
      mode = "0400";
    };
    # thinkpad_p15s_aliases.file = "${inputs.mysecrets}/thinkpad_p15s_aliases.age";
  };

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  # Symlink /etc paths to agenix secrets so other modules can reference them.
  # Using symlink mode (default) avoids the ownership mismatch that occurs
  # when environment.etc copies from a tmpfs source (results in nobody:nogroup).
  environment.etc = {
    "ssh/host_ssh.conf".source = config.age.secrets.tp-p14s-factify-ssh.path;
    "agenix/host_env.env".source = config.age.secrets.tp-p14s-factify-env.path;
  };
}
