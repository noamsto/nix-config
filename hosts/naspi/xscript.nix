{pkgs, ...}: let
  # Geekworm X-series expansion board scripts - defined once and reused
  xscript = pkgs.stdenv.mkDerivation {
    pname = "xscript";
    version = "2024-12-30";

    src = pkgs.fetchFromGitHub {
      owner = "geekworm-com";
      repo = "xscript";
      rev = "master";
      sha256 = "sha256-27eotcVbaggJMfP1OwBz47Xp5tHpWJKCZDLKtEKLNNc=";
    };

    installPhase = ''
      mkdir -p $out/bin
      # Only install service scripts, not install/uninstall scripts
      cp x-c1-fan.sh $out/bin/
      cp xPWR.sh $out/bin/
      cp xSoft.sh $out/bin/
      chmod +x $out/bin/*.sh
    '';

    meta = with pkgs.lib; {
      description = "Geekworm X-series expansion board service scripts for Raspberry Pi";
      homepage = "https://github.com/geekworm-com/xscript";
      license = licenses.gpl3;
      platforms = platforms.linux;
    };
  };
in {
  # Make xscript available in system packages
  environment.systemPackages = [
    xscript
  ];

  # Systemd services for Geekworm X-series expansion boards
  systemd.services = {
    # PWM-based fan control service
    x-c1-fan = {
      description = "PWM Fan Controller for X-C1 expansion board";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${xscript}/bin/x-c1-fan.sh";
        Restart = "always";
        User = "root";
        Group = "root";
      };
    };

    # Hardware power management service
    x-c1-pwr = {
      description = "Hardware Power Management & Safe Shutdown daemon";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${xscript}/bin/xPWR.sh 0 4 17";
        Restart = "always";
        User = "root";
        Group = "root";
      };
    };
  };
}
