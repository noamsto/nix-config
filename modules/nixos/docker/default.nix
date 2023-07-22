{
  config,
  pkgs,
  ...
}: {
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
  # virtualisation.docker.storageDriver = "btrfs"
}
