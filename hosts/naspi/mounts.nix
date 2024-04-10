{...}: {
  fileSystems."/mnt/main-ssd" = {
    device = "/dev/disk/by-uuid/330d520d-1661-457e-b0b8-355d56dd64ed";
    fsType = "ext4";
  };
}
