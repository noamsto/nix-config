# Evaluation fixture proving the exported modules need no specialArgs.
# nixosModules.home is what a consumer brings, because priors reads
# home-manager.users.
{self}: {...}: {
  imports = [
    self.nixosModules.default
    self.nixosModules.home
    self.nixosModules.core
    self.nixosModules.nice-looking-console
    ./hardware-configuration.nix
  ];

  hostname = "example";

  priors.personalStore = {
    id = "example-personal-store";
    remote = "ssh://git@example.invalid/example/personal-store.git";
  };
}
