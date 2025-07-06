{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/mmcblk0";
        content = {
          type = "gpt";
          partitions = {
            firmware = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "noatime" # Reduce writes
                  "data=writeback" # Better for flash storage
                  "barrier=0" # Reduce write barriers (microSD doesn't need them)
                ];
              };
            };
          };
        };
      };
    };
  };
}
