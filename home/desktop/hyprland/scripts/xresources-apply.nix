{pkgs}:
pkgs.writeShellApplication {
  name = "xresources-apply";
  runtimeInputs = [pkgs.xrdb];
  text = builtins.readFile ./xresources-apply.sh;
}
