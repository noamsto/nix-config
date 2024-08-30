{pkgs, ...}: let
  pre-suspend-script = pkgs.writeShellScript "pre-suspend.sh" ''
    # Add your pre-suspend commands here
    # For example:
    # pkill -u $USER some-process
    # ${pkgs.libnotify}/bin/notify-send "Suspending" "The system is going to sleep"
    echo "Running pre-suspend script"
  '';

  post-resume-script = pkgs.writeShellScript "post-resume.sh" ''
    # Add your post-resume commands here
    # For example:
    # ${pkgs.libnotify}/bin/notify-send "Resumed" "Welcome back!"
    echo "Running post-resume script"
  '';
in {
  systemd.user.services.pre-suspend = {
    Unit = {
      Description = "Pre-suspend actions";
      Before = ["sleep.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pre-suspend-script}";
      RemainAfterExit = true;
    };
    Install = {
      WantedBy = ["sleep.target"];
    };
  };

  systemd.user.services.post-resume = {
    Unit = {
      Description = "Post-resume actions";
      After = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${post-resume-script}";
    };
    Install = {
      WantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
