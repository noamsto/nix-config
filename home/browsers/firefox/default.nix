{
  config,
  pkgs,
  ...
}: {
  programs.firefox = {
    enable = true;
    # package = pkgs.firefox.override {
    #   cfg.nativeMessagingHosts.packages = [pkgs.plasma5Packages.plasma-browser-integration];
    # };
  };
  home.file.".mozilla/native-messaging-hosts/org.kde.plasma.browser_integration.json".source = "${pkgs.plasma-browser-integration}/lib/mozilla/native-messaging-hosts/org.kde.plasma.browser_integration.json";
}
