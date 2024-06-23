{
  pkgs,
  username,
  ...
}: {
  environment.systemPackages = with pkgs; [
    lazydocker
    docker-compose
  ];
  virtualisation.docker.enable = true;
  users.users.${username}.extraGroups = ["docker"];
}
