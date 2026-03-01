{config, ...}: {
  programs = {
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [config.username];
    };
    _1password.enable = true;
  };
}
