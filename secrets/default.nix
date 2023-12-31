# import & decrypt secrets in `mysecrets` in this module
{
  pkgs,
  username,
  inputs,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  environment.systemPackages = [
    inputs.agenix.packages."${pkgs.system}".default
  ];

  #   if you changed this key, you need to regenerate all encrypt files from the decrypt contents!
  age.identityPaths = [
    "/home/${username}/.ssh/id_ed25519"
  ];

  age.secrets.noams_password.file = "${inputs.mysecrets}/noams_password.age";
}
