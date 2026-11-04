{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.wayland.windowManager.hyprland;

  # Mirrors home-manager's own reloadConfig (hyprland/default.nix).
  reload = ''
    (
      XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
      if [[ -d "/tmp/hypr" || -d "$XDG_RUNTIME_DIR/hypr" ]]; then
        for i in $(${cfg.finalPackage}/bin/hyprctl instances -j | ${lib.getExe pkgs.jq} ".[].instance" -r); do
          ${cfg.finalPackage}/bin/hyprctl -i "$i" reload config-only
        done
      fi
    )
  '';

  # Mirrors home-manager's luaFileName: dots in the attr name are module
  # separators, so "a.b" lands at hypr/a/b.lua.
  luaFileName = name: "${builtins.replaceStrings ["."] ["/"] (lib.removeSuffix ".lua" name)}.lua";
in {
  # home-manager attaches its reload hook to hyprland.lua alone; extraLuaFiles
  # are written with only text/source (hyprland/lib.nix). Every binding here
  # lives in extraLuaFiles, so without this a rebind reaches disk and Hyprland
  # keeps serving the previous table — silently, until something restarts it.
  xdg.configFile = lib.mkIf (cfg.enable && cfg.package != null) (
    lib.mapAttrs' (name: _:
      lib.nameValuePair "hypr/${luaFileName name}" {onChange = reload;})
    cfg.extraLuaFiles
  );
}
