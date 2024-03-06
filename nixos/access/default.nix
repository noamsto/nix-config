{
  pkgs,
  config,
  username,
  ...
}: let
  access-tunnel = import ./access-tunnel.nix {inherit pkgs config;};
in {
  config.users.groups.fyde = {
    name = "fyde";
  };
  config.users.users.${username}.extraGroups = ["fyde"];

  config.environment.systemPackages = [access-tunnel];
  config.systemd.packages = [access-tunnel];
  config.systemd.services = {
    access-interface.wantedBy = ["milti-user.target"];
  };
}
