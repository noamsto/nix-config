{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  suspendScript = pkgs.writeShellScript "suspend-script" ''
    # check for fullscreen applications (video, games, video calls)
    if ${pkgs.hyprland}/bin/hyprctl activewindow | ${lib.getExe pkgs.ripgrep} -q "fullscreen: 1"; then
      exit 0
    fi

    # check for video players or games specifically
    active_class=$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${lib.getExe pkgs.jq} -r '.class')
    if [[ "$active_class" =~ (vlc|mpv|youtube-music|brave-browser|firefox|zoom|discord|teams) ]]; then
      exit 0
    fi

    # suspend if no inhibitors found
    ${pkgs.systemd}/bin/systemctl suspend
  '';

  brillo = lib.getExe pkgs.brillo;

  # timeout after which DPMS kicks in
  timeout = 300;
in {
  # screen idle
  services.hypridle = {
    enable = true;

    package = inputs.hypridle.packages.${pkgs.system}.hypridle;

    settings = {
      general = {
        lock_cmd = lib.getExe config.programs.hyprlock.package;
        before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = timeout - 10;
          # save the current brightness and dim the screen over a period of
          # 1 second
          on-timeout = "${brillo} -O; ${brillo} -u 1000000 -S 10";
          # brighten the screen over a period of 500ms to the saved value
          on-resume = "${brillo} -I -u 500000";
        }
        {
          inherit timeout;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = timeout + 10;
          on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
        }
      ];
    };
  };
}
