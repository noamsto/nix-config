#NOTE: This File is just for reference on how to add Host specific secrets (Work for example)
{
  config,
  inputs,
  ...
}: {
  age.secrets = {
    thinkpad_p14s_ssh.file = "${inputs.mysecrets}/thinkpad_p14s_ssh.age";
    thinkpad_p14s_aliases.file = "${inputs.mysecrets}/thinkpad_p14s_aliases.age";
  };

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  environment.etc = {
    "ssh/host_ssh.conf" = {
      source = config.age.secrets.thinkpad_p14s_ssh.path;
      mode = "0644";
    };
    "agenix/work_aliases.zsh" = {
      source = config.age.secrets.thinkpad_aliases.path;
      mode = "0644";
    };
  };
}
