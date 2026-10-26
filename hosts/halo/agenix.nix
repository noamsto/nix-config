{
  pkgs,
  inputs,
  ...
}: {
  imports = [inputs.agenix.nixosModules.default];

  environment.systemPackages = [inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default];

  age = {
    # The host key: a user key does not exist yet at activation time.
    identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets.noams_password.file = "${inputs.mysecrets}/noams_password.age";
  };
}
