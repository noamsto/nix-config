{
  config,
  pkgs,
  inputs,
  ...
}: {
  # Paperless-ngx document management system
  services.paperless = {
    enable = true;

    # Use agenix-encrypted password file
    passwordFile = config.age.secrets.paperless-naspi-password.path;

    # Store data on encrypted ZFS dataset
    dataDir = "/data/paperless/data";
    mediaDir = "/data/paperless/media";

    # Use local PostgreSQL database
    database.createLocally = true;

    # Network configuration - listen on all interfaces
    address = "0.0.0.0";
    port = 28981;

    settings = {
      # Hebrew + English OCR support
      PAPERLESS_OCR_LANGUAGE = "heb+eng";

      # Timezone configuration
      PAPERLESS_TIME_ZONE = "Asia/Jerusalem";

      # Network configuration
      PAPERLESS_ALLOWED_HOSTS = "naspi.local,naspi,localhost,127.0.0.1,192.168.3.6";
      PAPERLESS_URL = "http://naspi.local/paperless";

      # Enable subfolder access via /paperless
      PAPERLESS_FORCE_SCRIPT_NAME = "/paperless";
      PAPERLESS_STATIC_URL = "/paperless/static/";

      # OCR optimization settings
      PAPERLESS_OCR_USER_ARGS = {
        optimize = 1;
        pdfa_image_compression = "lossless";
      };

      # Document consumption settings
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
        "Thumbs.db"
      ];

      # Enable task workers for better performance
      PAPERLESS_TASK_WORKERS = 2;
      PAPERLESS_THREADS_PER_WORKER = 1;
    };
  };

  # Create directory structure on encrypted ZFS dataset
  systemd.tmpfiles.rules = [
    "d /data/paperless 0755 paperless paperless - -"
    "d /data/paperless/data 0755 paperless paperless - -"
    "d /data/paperless/media 0755 paperless paperless - -"
    "d /data/paperless/consume 0755 paperless paperless - -"
    "d /data/paperless/export 0755 paperless paperless - -"
  ];

  # Open firewall port for Paperless web interface
  networking.firewall.allowedTCPPorts = [
    28981 # Paperless web UI
  ];

  # Ensure Paperless starts after ZFS datasets are mounted
  systemd.services.paperless-scheduler.after = ["local-fs.target" "zfs-mount.service"];
  systemd.services.paperless-consumer.after = ["local-fs.target" "zfs-mount.service"];
  systemd.services.paperless-web.after = ["local-fs.target" "zfs-mount.service"];
  systemd.services.paperless-task-queue.after = ["local-fs.target" "zfs-mount.service"];
}
