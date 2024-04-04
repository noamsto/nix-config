{
  pkgs,
  config,
  ...
}: let
  access-tunnel = import ./access-tunnel.nix {inherit pkgs config;};
in {
  config.users.groups.fyde = {
    name = "fyde";
  };

  config.networking.networkmanager.unmanaged = ["fyde"];
  config.environment.systemPackages = [access-tunnel];
  config.systemd.packages = [access-tunnel];
  config.systemd.services = {
    access-interface.wantedBy = ["multi-user.target"];
    access-interface.after = ["network-online.target" "systemd-resolved.service"];
  };

  config.environment.shellAliases = {
    cga-fix-dns = ''
      sudo resolvectl dns fyde 192.0.2.4 192.0.2.5
    '';
  };
}
