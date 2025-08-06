{pkgs, ...}: let
  # Unified screen recording script
  recordScreenScript = builtins.readFile ./sh/record-screen.sh;
in {
  home.packages = [
    # Screenshot edit script (complementary to grimblast)
    (pkgs.writeShellScriptBin "screenshot-edit" (builtins.readFile ./sh/screenshot-edit.sh))

    # Unified screen recording script
    (pkgs.writeShellScriptBin "record-screen" recordScreenScript)

    # Screen recording scripts (using unified script with arguments)
    (pkgs.writeShellScriptBin "record-screen-mp4" ''
      exec ${pkgs.writeShellScript "record-screen" recordScreenScript} mp4
    '')

    (pkgs.writeShellScriptBin "record-screen-gif" ''
      exec ${pkgs.writeShellScript "record-screen" recordScreenScript} gif
    '')

    # System toggles
    (pkgs.writeShellScriptBin "system-toggles" (builtins.readFile ./sh/system-toggles.sh))
  ];
}
