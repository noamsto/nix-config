# Shared host configurations for both NixOS and Home Manager
# Only includes properties needed by both systems
{
  sshPublicKeys = {
    noams = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com";
  };

  thinkpad-p14s-g5 = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noam@factify.com";
    hostname = "thinkpad-p14s-g5";
    desktop.mode = "hyprland";
    machine.type = "laptop";
    profile = "work";
    laptop-scale = "2.0";
  };

  thinkpad-p14s-g6 = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "thinkpad-p14s-g6";
    desktop.mode = "hyprland";
    machine.type = "laptop";
    # Temporarily running g6 as an always-on headless server (SSH/tmux).
    # Set back to false to restore normal laptop suspend behavior. Read by both
    # the NixOS host and standalone HM so `nh os`/`nh home` stay in sync.
    machine.serverMode = true;
    profile = "personal";
    laptop-scale = "1.25";
  };

  halo = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "halo";
    desktop.mode = "none";
    # "desktop" not "server": nixos/core/pc.nix gates pipewire (alsa.support32Bit,
    # needed by Steam) and bluetooth (controller) behind machine.isPC.
    machine.type = "desktop";
    # Headless by construction — no display manager, reached only over ssh. Binds
    # the startup tmux session to default.target instead of a
    # graphical-session.target that never arrives, so the remote session picker
    # has a server to attach to. Also drops fprintd; this box has no sensor.
    machine.serverMode = true;
    profile = "personal";
  };

  mbp-m4-pro = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "mbp-m4-pro";
    desktop.mode = "none";
    machine.type = "laptop";
    profile = "personal";
  };
}
