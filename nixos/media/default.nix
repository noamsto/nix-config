{...}: {
  imports = [
    ./radaar.nix
    ./transmission.nix
    ./prowlarr.nix
    ./bazarr.nix
    ./sonarr.nix
  ];
  users.groups.media = {};
}
