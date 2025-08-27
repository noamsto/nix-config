# Shared shell aliases for all hosts
# Dynamically generates aliases based on available configurations
{config, ...}: let
  # Current host profile for smart defaults
  currentProfile = config.profile or "personal";

  # Generate HM config name based on profile and desktop
  getHmConfig = profile: desktop:
    if profile == "work"
    then "noams-${desktop}-work"
    else if desktop == "kde"
    then "noams-kde"
    else "noams-${desktop}";

  # Default HM config for current host
  defaultHmConfig = getHmConfig currentProfile (config.desktop.mode or "hyprland");

  # Alternative configs for testing
  altPersonalConfig = getHmConfig "personal" (config.desktop.mode or "hyprland");
  altWorkConfig = getHmConfig "work" (config.desktop.mode or "hyprland");
in {
  environment.shellAliases = {
    # Remote Pi rebuilds
    naspi-rebuild-switch = ''
      NIX_SSHOPTS="-A" nixos-rebuild --flake .#naspi --use-remote-sudo --build-host noams@naspi.local --target-host noams@naspi.local switch
    '';
  };
}
