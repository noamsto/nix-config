{
  lib,
  pkgs,
  ...
}:
# Coworker Macs on the office LAN advertise themselves as AirPlay receivers, so
# PipeWire's RAOP discovery (nixos/core/pc.nix) lists every one as a sink.
# WirePlumber has no JSON rule for RAOP-discovered nodes, so load a Lua hook
# that destroys any raop_sink whose AirPlay friendly name marks it as a Mac.
# The hook re-fires on re-announce, so a woken Mac is re-hidden automatically.
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  # WirePlumber 0.5 finds custom scripts under XDG_DATA_HOME, not XDG_CONFIG_HOME.
  xdg.dataFile."wireplumber/scripts/hide-macbook-raop.lua".source = ./hide-macbook-raop.lua;

  xdg.configFile."wireplumber/wireplumber.conf.d/99-hide-macbook-raop.conf".text = ''
    wireplumber.components = [
      {
        name = hide-macbook-raop.lua, type = script/lua
        provides = hooks.custom.hide-macbook-raop
      }
    ]

    wireplumber.profiles = {
      main = {
        hooks.custom.hide-macbook-raop = required
      }
    }
  '';
}
