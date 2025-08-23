{pkgs, ...}: let
  # Define shader files
  cursorSmearShader = ./shaders/cursor_smear.glsl;
  cursorSmearFadeShader = ./shaders/cursor_smear_fade.glsl;
in {
  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;
    installVimSyntax = true;
    installBatSyntax = true;
    settings = {
      background-opacity = 0.9;
      mouse-hide-while-typing = true;
      confirm-close-surface = false;

      # Command to run tmux attach script - target the main session created by systemd service
      # Set TMUX_TMPDIR to match the systemd service location
      command = "TMUX_TMPDIR=/run/user/$(id -u) tmux attach || TMUX_TMPDIR=/run/user/$(id -u) tmux new -s main";

      # Cursor smear shaders available for future use when ghostty is updated
      # custom-shader = "${config.xdg.configHome}/ghostty/shaders/cursor_smear.glsl";
      # custom-shader = "${config.xdg.configHome}/ghostty/shaders/cursor_smear_fade.glsl";
    };
  };

  # Ensure shader files are available at runtime
  xdg.configFile."ghostty/shaders/cursor_smear.glsl".source = cursorSmearShader;
  xdg.configFile."ghostty/shaders/cursor_smear_fade.glsl".source = cursorSmearFadeShader;
}
