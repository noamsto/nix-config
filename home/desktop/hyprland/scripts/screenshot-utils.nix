{pkgs, ...}: let
  # Screenshot helper script
  screenshotHelperScript = builtins.readFile ./sh/screenshot-helper.sh;
  # Satty copy wrapper - saves image and copies path
  sattyCopyPathScript = builtins.readFile ./sh/satty-copy-path.sh;
  # Satty wrapper for grimblast - converts positional arg to --filename
  sattyWrapperScript = builtins.readFile ./sh/satty-wrapper.sh;
  # Grimblast edit wrapper - uses save instead of edit to unfreeze screen
  grimblastEditWrapperScript = builtins.readFile ./sh/grimblast-edit-wrapper.sh;
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

    # Grimblast edit wrapper - takes screenshot and opens in satty without keeping screen frozen
    (pkgs.writeShellScriptBin "grimblast-satty" grimblastEditWrapperScript)

    # System toggles
    (pkgs.writeShellScriptBin "system-toggles" (builtins.readFile ./sh/system-toggles.sh))

    # Screenshot menu using vicinae
    (pkgs.writeShellScriptBin "screenshot-menu" (builtins.readFile ./sh/screenshot-menu.sh))
  ];
}
