{pkgs, ...}: let
  xscript = import ./xscript.nix {inherit pkgs;};
in {
  config.environment.systemPackages = [xscript];
  config.systemd.packages = [xscript];
  config.systemd.services = {
    x-c1-fan.wantedBy = ["multi-user.target"];
    # x-c1-fan.wantedBy = ["multi-user.target"];
  };
}
