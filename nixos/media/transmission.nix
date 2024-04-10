{pkgs, ...}: {
  services.transmission = {
    enable = true;
    group = "media";
    openFirewall = true;
    webHome = "${pkgs.flood-for-transmission}";
    openRPCPort = true; #Open firewall for RPC
    settings = {
      idle-seeding-limit = 30;
      idle-seedi-ng-limit-enabled = true;
      ratio-limit = 2;
      ratio-limit-enabled = true;
      incomplete-dir-enabled = true;
      incomplete-dir = "/mnt/main-ssd/Shares/Public/Downloads/Incomplete";
      download-dir = "/mnt/main-ssd/Shares/Public/Downloads/Complete";
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist = "127.0.0.*,192.168.*";
      rpc-host-whitelist-enabled = "noams-barracuda";
      peer-port = 51414;
    };
  };
}
