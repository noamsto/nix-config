{...}: {
  services.bazarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };
}
