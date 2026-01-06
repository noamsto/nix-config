{
  config,
  pkgs,
  ...
}: {
  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.${config.username} = {
    isNormalUser = true;
    description = config.user-full-name;
    extraGroups = ["networkmanager" "wheel" "video" "input" "i2c"];
    hashedPasswordFile = config.age.secrets.noams_password.path;
    shell = pkgs.fish;
  };

  # Enable fish shell system-wide
  programs.fish.enable = true;
}
