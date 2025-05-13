{...}: {
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Fira Code Nerd Font:size=11, Noto Color Emoji:size=11";
        dpi-aware = "yes";
      };
      # tweak = {
      #   grapheme-width-method = "wcswidth";
      # };

      text-bindings = {
        "\\x1b[72;6u" = "Control+Shift+h";
        "\\x1b[74;6u" = "Control+Shift+j";
        "\\x1b[75;6u" = "Control+Shift+k";
        "\\x1b[76;6u" = "Control+Shift+l";

        "\\x1b[105;5u" = "Control+i";

        "\\x1b[46;5u" = "Control+period";
        "\\x1b[44;5u" = "Control+comma";
        "\\x1b[59;5u" = "Control+semicolon";

        "\\x1b[13;2u" = "Shift+Return";
      };

      mouse = {
        hide-when-typing = "yes";
      };
    };
  };
}
