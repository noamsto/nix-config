# Go Bills - Shared Bills Management Service
{
  config,
  pkgs,
  inputs,
  ...
}: let
  # Get package from flake input
  go-bills = inputs.go-bills.packages.aarch64-linux.default;

  # Tesseract with Hebrew support for OCR
  tesseractWithLangs = pkgs.tesseract5.override {enableLanguages = ["eng" "heb"];};

  # Service configuration
  dataDir = "/var/lib/go-bills";
  uploadsDir = "/data/bills";
  dbName = "go_bills";
  dbUser = "go-bills";
  dbPassword = "go-bills";
  port = 8082;
in {
  # Create user and group
  users.users.go-bills = {
    isSystemUser = true;
    group = "go-bills";
    home = dataDir;
    createHome = true;
  };
  users.groups.go-bills = {};

  # Create directories
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 go-bills go-bills - -"
    "d ${uploadsDir} 0750 go-bills go-bills - -"
  ];

  # PostgreSQL database
  services.postgresql = {
    enable = true;
    ensureDatabases = [dbName];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];
  };

  # Set password after PostgreSQL starts
  systemd.services.go-bills-db-setup = {
    description = "Set up go-bills database password";
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };
    script = ''
      ${config.services.postgresql.package}/bin/psql -c "ALTER USER \"${dbUser}\" WITH PASSWORD '${dbPassword}';" || true
    '';
  };

  # Main service
  systemd.services.go-bills = {
    description = "Go Bills - Shared Bills Management";
    after = ["network.target" "postgresql.service" "go-bills-db-setup.service"];
    wants = ["postgresql.service"];
    wantedBy = ["multi-user.target"];

    preStart = ''
      # Copy static files and migrations to data directory
      rm -rf ${dataDir}/static ${dataDir}/migrations
      cp -r ${go-bills}/share/go-bills/static ${dataDir}/
      cp -r ${go-bills}/share/go-bills/migrations ${dataDir}/
      chown -R go-bills:go-bills ${dataDir}/static ${dataDir}/migrations
    '';

    serviceConfig = {
      Type = "simple";
      User = "go-bills";
      Group = "go-bills";
      WorkingDirectory = dataDir;
      ExecStart = "${go-bills}/bin/bills";
      Restart = "on-failure";
      RestartSec = 5;

      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [dataDir uploadsDir];
    };

    environment = {
      DB_HOST = "localhost";
      DB_PORT = "5432";
      DB_NAME = dbName;
      DB_USER = dbUser;
      DB_PASSWORD = dbPassword;
      SESSION_SECRET = "naspi-bills-session-2024";
      PORT = toString port;
      GIN_MODE = "release";
      TESSDATA_PREFIX = "${tesseractWithLangs}/share/tessdata";
    };

    path = [tesseractWithLangs pkgs.poppler_utils];
  };
}
