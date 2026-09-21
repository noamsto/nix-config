{inputs, ...}: {
  age.secrets = {
    nixAccessTokens = {
      file = "${inputs.mysecrets}/personal-nix-access-tokens.age";
      mode = "0440";
      group = "wheel";
    };
  };

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];
}
