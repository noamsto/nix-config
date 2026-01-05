{pkgs, ...}: let
  fullscreen-toggle = pkgs.writeShellApplication {
    name = "fullscreen-toggle";
    runtimeInputs = with pkgs; [hyprland jq coreutils];
    text = builtins.readFile ./sh/fullscreen-toggle.sh;
  };
in {
  home.packages = [fullscreen-toggle];
}
