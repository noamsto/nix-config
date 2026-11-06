# Runnable lock-commit: the same fish function body Home Manager installs, with
# an empty watch list, for CI (the update bot) and `nix run .#lock-commit`.
{
  lib,
  pkgs,
  writeTextFile,
}:
writeTextFile {
  name = "lock-commit";
  executable = true;
  destination = "/bin/lock-commit";
  text = ''
    #!${pkgs.fish}/bin/fish
    ${import ../home/terminal/fish/lock-commit.nix {
      inherit pkgs lib;
      watchedInputs = [];
    }}
    # git must be on PATH for the function's `command git` calls.
    set -p PATH ${lib.makeBinPath [pkgs.git pkgs.coreutils]}
    lock-commit $argv
  '';
  meta.mainProgram = "lock-commit";
}
