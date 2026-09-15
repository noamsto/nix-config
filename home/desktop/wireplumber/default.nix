{
  lib,
  pkgs,
  ...
}:
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  xdg = {
    # Coworker Macs on the office LAN advertise themselves as AirPlay receivers, so
    # PipeWire's RAOP discovery (nixos/core/pc.nix) lists every one as a sink.
    # WirePlumber has no JSON rule for RAOP-discovered nodes, so load a Lua hook
    # that destroys any raop_sink whose AirPlay friendly name marks it as a Mac.
    # The hook re-fires on re-announce, so a woken Mac is re-hidden automatically.

    # WirePlumber 0.5 finds custom scripts under XDG_DATA_HOME, not XDG_CONFIG_HOME.
    dataFile."wireplumber/scripts/hide-macbook-raop.lua".source = ./hide-macbook-raop.lua;

    configFile = {
      "wireplumber/wireplumber.conf.d/99-hide-macbook-raop.conf".text = ''
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

      # The AMD HDMI codec exposes four pins whether or not a display is attached.
      # Opened through UCM, its HiFi profile activates all four at once and carries no
      # port availability, so the empty pins surface as selectable sinks that silently
      # swallow audio. ACP reads the per-pin jack kctls instead, publishing sinks only
      # for pins with a live ELD and updating them on hotplug. The trade-off is that
      # ACP has no combination profile here, so only one HDMI output exists at a time.
      # Both rules match on card- and profile-level names rather than the PCI path, so
      # they apply unchanged on every host importing this module.
      "wireplumber/wireplumber.conf.d/99-alsa-rules.conf".text = ''
        monitor.alsa.rules = [
          {
            matches = [
              { device.product.name = "Radeon High Definition Audio Controller" }
            ]
            actions = {
              update-props = {
                api.alsa.use-ucm = false
              }
            }
          }
          {
            matches = [
              { device.profile.name = "HiFi: Speaker: sink" }
            ]
            actions = {
              update-props = {
                node.description = "Laptop Speakers"
              }
            }
          }
        ]
      '';
    };
  };
}
