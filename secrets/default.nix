# import & decrypt secrets in `mysecrets` in this module
{
  pkgs,
  inputs,
  config,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  environment.systemPackages = [
    # (inputs.agenix.packages."${pkgs.stdenv.hostPlatform.system}".default.override {ageBin = "${pkgs.rage}/bin/rage";})
    inputs.agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
  ];

  #   if you changed this key, you need to regenerate all encrypt files from the decrypt contents!
  age.identityPaths =
    if config.machine.type == "server"
    then [
      "/etc/ssh/ssh_host_ed25519_key"
    ]
    else [
      "/home/${config.username}/.ssh/id_ed25519"
    ];

  age.secrets.noams_password.file = "${inputs.mysecrets}/noams_password.age";
  age.secrets.paperless-naspi-password.file = "${inputs.mysecrets}/paperless-naspi-admin-password.age";

  nix = {
    extraOptions =
      if config.age.secrets ? nixAccessTokens
      then ''
        !include ${config.age.secrets.nixAccessTokens.path}
      ''
      else "";
  };
}
