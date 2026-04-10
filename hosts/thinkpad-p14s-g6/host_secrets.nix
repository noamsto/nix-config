{
  inputs,
  config,
  ...
}: {
  age.secrets = {
    opencode-server-password = {
      file = "${inputs.mysecrets}/opencode-server-password.age";
      owner = config.username;
      mode = "0400";
    };
  };

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  environment.etc = {
    "agenix/opencode-server-password.env" = {
      source = config.age.secrets.opencode-server-password.path;
      mode = "0400";
      user = config.username;
    };
  };
}
