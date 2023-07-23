{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    lazydocker
    docker-compose

    # Kubernetes
    kubectl
    k9s
  ];
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
}
