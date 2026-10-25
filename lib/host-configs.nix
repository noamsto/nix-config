# Shared host configurations for both NixOS and Home Manager
# Only includes properties needed by both systems
{
  sshPublicKeys = {
    # The laptop key, carried on the machines that unlock behind a passphrase.
    noams = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com";

    # halo's own key rather than a copy of `noams`: it is the one host that
    # boots straight to a running system with no passphrase (TPM auto-unlock, no
    # display manager) while sitting under the TV, and it runs agents
    # unattended. Keeping it separate means revoking halo does not re-key the
    # laptops. Halo needs to reach out, not just be reached: its own session
    # picker lists tp-g6 and mbp, and neither runs Tailscale SSH.
    halo = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQ6DaFgFtOJJHI5KE3YklX2NS+wxRXfzPUIFUaTvh5u noams@halo";
  };

  tp-g6 = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "tp-g6";
    desktop.mode = "hyprland";
    machine.type = "laptop";
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
    agentDashboard.enable = true;
  };

  mbp-m4-pro = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "mbp-m4-pro";
    desktop.mode = "none";
    machine.type = "laptop";
  };
}
