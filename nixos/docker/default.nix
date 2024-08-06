{
  pkgs,
  config,
  ...
}: {
  environment.systemPackages = with pkgs; [
    lazydocker
    docker-compose
  ];
  virtualisation.docker.enable = true;
  users.users.${config.username}.extraGroups = ["docker"];
}
