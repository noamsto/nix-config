{pkgs, ...}: let
  # Unified screen recording script
  recordScreenScript = builtins.readFile ./sh/record-screen.sh;
  # Screenshot helper script
  screenshotHelperScript = builtins.readFile ./sh/screenshot-helper.sh;
  # Satty copy wrapper - saves image and copies path
  sattyCopyPathScript = builtins.readFile ./sh/satty-copy-path.sh;
  # Satty wrapper for grimblast - converts positional arg to --filename
  sattyWrapperScript = builtins.readFile ./sh/satty-wrapper.sh;
in {
  home.packages = [
    # Screenshot helper script with proper scaling and satty integration
    (pkgs.writeShellScriptBin "screenshot-helper" screenshotHelperScript)

    # Screenshot edit script (complementary to grimblast)
    (pkgs.writeShellScriptBin "screenshot-edit" (builtins.readFile ./sh/screenshot-edit.sh))

    # Satty copy wrapper - copies file path instead of image data
    (pkgs.writeShellScriptBin "satty-copy-path" sattyCopyPathScript)

    # Satty wrapper for grimblast - converts positional arg to --filename flag
    (pkgs.writeShellScriptBin "satty-wrapper" sattyWrapperScript)

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
