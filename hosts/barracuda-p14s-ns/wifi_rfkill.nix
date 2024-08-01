{pkgs, ...}: {
  systemd.services = {
    ath11k-suspend = {
      enable = true;
      description = "Suspend: rmmod ath11k_pci";
      before = ["sleep.target"];
      wantedBy = ["sleep.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.kmod}/bin/rmmod ath11k_pci";
      };
    };
    ath11k-resume = {
      enable = true;
      description = "Resume: modprobe ath11k_pci";
      after = ["suspend.target"];
      wantedBy = ["suspend.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.kmod}/bin/modprobe ath11k_pci";
      };
    };
  };
}
