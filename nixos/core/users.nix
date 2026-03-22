{
  config,
  pkgs,
  ...
}: {
  users.users.${config.username} = {
    isNormalUser = true;
    description = config.user-full-name;
    extraGroups = ["networkmanager" "wheel" "video" "input" "i2c"];
    hashedPasswordFile = config.age.secrets.noams_password.path;
    shell = pkgs.fish;
  };

  programs.fish.enable = true;
}
