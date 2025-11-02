{pkgs, ...}: let
  # Unified screen recording script
  recordScreenScript = builtins.readFile ./sh/record-screen.sh;
  # Screenshot helper script
  screenshotHelperScript = builtins.readFile ./sh/screenshot-helper.sh;
in {
  home.packages = [
    # Screenshot helper script with proper scaling and satty integration
    (pkgs.writeShellScriptBin "screenshot-helper" screenshotHelperScript)

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

    # Screenshot menu using vicinae
    (pkgs.writeShellScriptBin "screenshot-menu" (builtins.readFile ./sh/screenshot-menu.sh))
  ];
}
