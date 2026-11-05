{
  config,
  lib,
  ...
}:
lib.mkIf config.desktop.isEnabled {
  programs = {
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [config.username];
    };
    _1password.enable = true;

    # Writes /etc/chromium/policies only (no browser). Force-installs 1Password
    # into every Chromium profile, including the Playwright MCP's own.
    chromium = {
      enable = true;
      extensions = ["aeblfdkhhhdcdjpifhhbdiojplfjncoa"];
    };
  };
}
