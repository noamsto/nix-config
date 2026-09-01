{
  config,
  lib,
  ...
}:
lib.mkIf config.desktop.isEnabled {
  programs = {
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [config.username];
    };
    _1password.enable = true;
  };
}
