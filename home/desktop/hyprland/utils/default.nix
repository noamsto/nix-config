{...}: {
  imports = [
    ./hypridle.nix
    ./screen-lock.nix # Unified screen locking solution
    ./wleave.nix # Modern logout menu (replaced wlogout)
  ];
}
