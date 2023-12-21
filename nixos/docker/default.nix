{
  config,
  pkgs,
  username,
  ...
}: {
  environment.systemPackages = with pkgs; [
    lazydocker
    docker-compose
  ];
  virtualisation.docker.enable = true;
  # virtualisation.docker.rootless = {
  #   enable = true;
  #   setSocketVariable = true;
  #   daemon.settings = {
  #     "dns" = ["8.8.8.8"];
  #   };
  # };
  users.users.${username}.extraGroups = ["docker"];
}
