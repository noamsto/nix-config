# Shared host configurations for both NixOS and Home Manager
# Only includes properties needed by both systems
{
  sshPublicKeys = {
    noams = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com";
  };

  thinkpad-p14s = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "thinkpad-p14s";
    desktop.mode = "hyprland";
    machine.type = "laptop";
    profile = "personal";
  };

  thinkpad-p14s-g5 = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noam@factify.com";
    hostname = "thinkpad-p14s-g5";
    desktop.mode = "hyprland";
    machine.type = "laptop";
    profile = "work";
  };
}
