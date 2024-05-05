{
  config,
  inputs,
  ...
}: {
  age.secrets = {
    barracuda_ssh.file = "${inputs.mysecrets}/barracuda_ssh.age";
    barracuda_aliases.file = "${inputs.mysecrets}/barracuda_aliases.age";
  };

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  environment.etc = {
    "ssh/host_ssh.conf" = {
      source = config.age.secrets.barracuda_ssh.path;
      mode = "0644";
    };
    "agenix/work_aliases.zsh" = {
      source = config.age.secrets.barracuda_aliases.path;
      mode = "0644";
    };
  };
}
