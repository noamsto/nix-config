{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    lazydocker
    docker-compose
  ];
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
}
