{
  pkgs,
  inputs,
  config,
  ...
}: {
  imports = [inputs.agenix.nixosModules.default];

  environment.systemPackages = [inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default];

  age = {
    # Changing this key means re-encrypting every secret to the new recipient.
    identityPaths = ["/home/${config.username}/.ssh/id_ed25519"];
    secrets.noams_password.file = "${inputs.mysecrets}/noams_password.age";
  };
}
