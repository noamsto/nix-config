{username, ...}: {
  services.samba = {
    enable = true;
    securityType = "user";
    openFirewall = true;
    extraConfig = ''
      workgroup = WORKGROUP
      server string = smb-naspi
      netbios name = smb-naspi
      security = user
      hosts allow = 192.168. 127.0.0.1 localhost
      hosts deny = 0.0.0.0/0
      guest account = nobody
      map to guest = bad user
    '';
    shares = {
      public = {
        path = "/mnt/main-ssd/Shares/Public";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "create mask" = "0644";
        "directory mask" = "0775";
        "force user" = username;
        "force group" = "naspi";
      };
      private = {
        path = "/mnt/main-ssd/Shares/Private";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0775";
        "force user" = username;
        "force group" = "naspi";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
    discovery = true;
  };

  networking.firewall.enable = true;
  networking.firewall.allowPing = true;
}
