{
  config,
  pkgs,
  agenix,
  mysecrets,
  username,
  ...
}: {
  age.secrets = {
    barracuda_ssh.file = "${mysecrets}/barracuda_ssh.age";
    barracuda_aliases.file = "${mysecrets}/barracuda_aliases.age";
  };

  age.identityPaths = [
    "/home/${username}/.ssh/barracuda_ed25519_key"
  ];

  environment.etc = {
    "ssh/host_ssh.conf"= {
      source = config.age.secrets.barracuda_ssh.path;
      mode = "0644";
    };
    "agenix/work_aliases.zsh"= {
      source = config.age.secrets.barracuda_aliases.path;
      mode = "0644";
    };
  };
}
