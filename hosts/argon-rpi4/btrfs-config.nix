# Btrfs configuration and utilities for Raspberry Pi 4
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Enable btrfs support
  boot.supportedFilesystems = ["btrfs"];

  # Install btrfs utilities
  environment.systemPackages = with pkgs; [
    btrfs-progs
    compsize # Check compression ratios
    inotify-tools # For monitoring file changes
  ];

  # Btrfs maintenance services
  services.btrfs = {
    autoScrub = {
      enable = true;
      interval = "weekly";
      fileSystems = ["/"];
    };
  };

  # Optional: Automatic snapshots with btrbk
  # Uncomment and configure as needed
  # services.btrbk.instances.system = {
  #   onCalendar = "hourly";
  #   settings = {
  #     timestamp_format = "long-iso";
  #     preserve_day_of_week = "monday";
  #     preserve_hour_of_day = "6";
  #
  #     volume."/" = {
  #       target = "/.snapshots";
  #       subvolume = {
  #         "@" = {
  #           snapshot_preserve_min = "2d";
  #           snapshot_preserve = "14d 4w 12m";
  #         };
  #         "@home" = {
  #           snapshot_preserve_min = "2d";
  #           snapshot_preserve = "14d 4w 12m";
  #         };
  #       };
  #     };
  #   };
  # };

  # Swapfile configuration (optimized for 8GB RAM Pi4)
  # With 8GB RAM, you may not need swap for normal use, but it's good for:
  # - Emergency situations
  # - Memory-intensive builds
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 4096; # 4GB - good balance for 8GB system
    }
  ];

  # Btrfs-specific kernel parameters for Raspberry Pi 4 (8GB RAM)
  boot.kernelParams = [
    # Optimize for SSD
    "rootflags=compress=zstd:3,noatime,ssd"
  ];

  # Additional 8GB RAM optimizations
  boot.kernel.sysctl = {
    # Btrfs-specific optimizations for 8GB RAM
    "vm.dirty_expire_centisecs" = 3000; # 30 seconds
    "vm.dirty_writeback_centisecs" = 500; # 5 seconds

    # More aggressive read-ahead for better performance
    "vm.page-cluster" = 3; # Read 8 pages at once (default is 3)

    # Memory allocation optimizations
    "vm.min_free_kbytes" = 131072; # 128MB reserved (recommended for 8GB)
  };
}
