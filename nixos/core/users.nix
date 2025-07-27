{config, ...}: {
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${config.username} = {
    isNormalUser = true;
    description = config.user-full-name;
    extraGroups = ["adbusers" "networkmanager" "wheel" "video" "input"];
    hashedPasswordFile = config.age.secrets.noams_password.path;
  };
}
