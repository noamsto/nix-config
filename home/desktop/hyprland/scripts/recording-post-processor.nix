{pkgs, ...}: let
  recordingPostProcessorScript = builtins.readFile ./sh/recording-post-processor.sh;

  # Use writeShellApplication for better environment handling
  recordingPostProcessor = pkgs.writeShellApplication {
    name = "recording-post-processor";
    runtimeInputs = with pkgs; [
      bash
      ffmpeg
      libnotify
      wl-clipboard
      inotify-tools
      coreutils
      jq
      vicinae
    ];
    text = recordingPostProcessorScript;
  };
in {
  # Install the post-processor script
  home.packages = [
    recordingPostProcessor
  ];

  # Systemd user service to run the post-processor
  systemd.user.services.recording-post-processor = {
    Unit = {
      Description = "Screen recording post-processor with GIF conversion";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${recordingPostProcessor}/bin/recording-post-processor";
      Restart = "on-failure";
      RestartSec = 5;

      # Inherit Wayland display for vicinae dmenu
      PassEnvironment = ["WAYLAND_DISPLAY" "XDG_RUNTIME_DIR" "DISPLAY"];
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
