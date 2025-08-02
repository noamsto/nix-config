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

  brightnessctl = lib.getExe pkgs.brightnessctl;

  # timeout after which DPMS kicks in
  timeout = 300;
in {
  # screen idle
  services.hypridle = {
    enable = true;

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
          on-timeout = "${brightnessctl} -s set 10%";
          # restore the saved brightness value
          on-resume = "${brightnessctl} -r";
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
