{pkgs, ...}:
pkgs.writeShellApplication {
  name = "claude-statusline";

  runtimeInputs = with pkgs; [jq coreutils];

  excludeShellChecks = ["SC2155" "SC2154"];

  text = builtins.readFile ./status-line.sh;
}
