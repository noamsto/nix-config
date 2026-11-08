# Desktop evaluation fixture: the same exported modules as hosts/example, but
# with a Hyprland laptop, so nixos/desktop, nixos/hyprland, nixos/laptop and
# home/desktop (theming, browsers) are evaluated before merge. An input bump
# that removes an option only the desktop modules use then fails CI here.
#
# Evaluation only, by design: CI never builds this host. A full desktop closure
# is too expensive; `nix flake check --no-build` evaluating it is the point.
{self}: {...}: {
  imports = [
    self.nixosModules.default
    self.nixosModules.home
    self.nixosModules.core
    self.nixosModules.nice-looking-console
    ../example/hardware-configuration.nix
  ];

  hostname = "example-desktop";

  desktop.mode = "hyprland";
  machine.type = "laptop";

  priors.personalStore = {
    id = "example-personal-store";
    remote = "ssh://git@example.invalid/example/personal-store.git";
  };
}
