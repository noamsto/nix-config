{
  pkgs,
  config,
  lib,
  ...
}: {
  # Set your time zone.
  time.timeZone = "Asia/Jerusalem";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ADDRESS = "en_IL";
    LC_IDENTIFICATION = "en_IL";
    LC_MEASUREMENT = "en_IL";
    LC_MONETARY = "en_IL";
    LC_NAME = "en_IL";
    LC_NUMERIC = "en_IL";
    LC_PAPER = "en_IL";
    LC_TELEPHONE = "en_IL";
    LC_TIME = "en_IL";
  };

  # Only install fonts on desktop/laptop machines (not servers)
  # all fonts are linked to /nix/var/nix/profiles/system/sw/share/X11/fonts
  fonts = lib.mkIf (config.machine.type != "server") {
    # use fonts specified by user rather than default ones
    enableDefaultPackages = false;
    fontDir.enable = true;

    packages = with pkgs; [
      # icon fonts
      material-design-icons
      font-awesome

      noto-fonts
      noto-fonts-emoji
      noto-fonts-extra

      # Chinese
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif

      source-sans
      source-serif

      # nerdfonts
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      nerd-fonts.ubuntu

      inter-nerdfont
    ];

    # user defined fonts
    # the reason there's Noto Color Emoji everywhere is to override DejaVu's
    # B&W emojis that would sometimes show instead of some Color emojis
    fontconfig.defaultFonts = {
      serif = [
        "Noto Serif"
        "Noto Serif CJK SC"
        "Noto Serif CJK TC"
        "Noto Serif CJK JP"
        "Source Serif Pro"
        "Noto Color Emoji"
      ];
      sansSerif = [
        "Inter Nerd Font"
        "Noto Sans"
        "Noto Sans CJK SC"
        "Noto Sans CJK TC"
        "Noto Sans CJK JP"
        "Source Sans Pro"
        "Noto Color Emoji"
      ];
      monospace = [
        "Fira Code Nerd Font"
        "JetBrains Mono Nerd Font"
        "Symbols Nerd Font Mono"
        "Noto Sans Symbols"
        "Noto Sans Symbols 2"
        "Noto Sans Mono CJK SC"
        "Noto Sans Mono CJK TC"
        "Noto Sans Mono CJK JP"
        "Noto Color Emoji"
      ];
      emoji = ["Noto Color Emoji" "Font Awesome 6 Free"];
    };
  };
}
