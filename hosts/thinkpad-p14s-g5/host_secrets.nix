#NOTE: This File is just for reference on how to add Host specific secrets (Work for example)
{
  config,
  inputs,
  ...
}: {
  age.secrets = {
    tp-p14s-factify-ssh.file = "${inputs.mysecrets}/tp-p14s-factify-ssh.age";
    tp-p14s-factify-env.file = "${inputs.mysecrets}/tp-p14s-factify-env.age";
    nixAccessTokens.file = "${inputs.mysecrets}/tp-p14s-factify-nix-access-tokens.age";
    # thinkpad_p15s_aliases.file = "${inputs.mysecrets}/thinkpad_p15s_aliases.age";
  };

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  environment.etc = {
    "ssh/host_ssh.conf" = {
      source = config.age.secrets.tp-p14s-factify-ssh.path;
      mode = "0644";
    };
    "agenix/work_env.env" = {
      source = config.age.secrets.tp-p14s-factify-env.path;
      mode = "0644";
    };
    # "agenix/work_aliases.zsh" = {
    #   source = config.age.secrets.thinkpad_aliases.path;
    #   mode = "0644";
    # };
  };
}
