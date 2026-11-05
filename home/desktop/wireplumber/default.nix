{
  lib,
  pkgs,
  ...
}: let
  # ACP names the first HDMI pin's mapping plainly and suffixes the rest.
  hdmiMapping = pin:
    if pin == 0
    then "hdmi-stereo"
    else "hdmi-stereo-extra${toString pin}";

  hdmiPins = [0 1 2 3];

  # Every non-empty subset, each ascending because pins are appended in order.
  pinSubsets =
    lib.filter (subset: subset != [])
    (lib.foldl' (acc: pin: acc ++ map (subset: subset ++ [pin]) acc) [[]] hdmiPins);

  # Low priority keeps find-best-profile off these; the hook selects the right
  # one explicitly, and a stock single-pin profile stays the fallback.
  comboProfile = pins: ''
    [Profile output:hdmi-combo-${lib.concatMapStringsSep "-" toString pins}]
    description = Digital Stereo (HDMI ${lib.concatMapStringsSep "+" toString pins})
    output-mappings = ${lib.concatMapStringsSep " " hdmiMapping pins}
    priority = 1
  '';

  hdmiComboProfiles = pkgs.writeText "hdmi-combo-profiles.conf" ''
    .include ${pkgs.pipewire}/share/alsa-card-profile/mixer/profile-sets/default.conf

    ${lib.concatMapStringsSep "\n" comboProfile pinSubsets}
  '';
in
  lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    xdg = {
      # Coworker Macs on the office LAN advertise themselves as AirPlay receivers, so
      # PipeWire's RAOP discovery (nixos/core/pc.nix) lists every one as a sink.
      # WirePlumber has no JSON rule for RAOP-discovered nodes, so load a Lua hook
      # that destroys any raop_sink whose AirPlay friendly name marks it as a Mac.
      # The hook re-fires on re-announce, so a woken Mac is re-hidden automatically.

      # WirePlumber 0.5 finds custom scripts under XDG_DATA_HOME, not XDG_CONFIG_HOME.
      dataFile = {
        "wireplumber/scripts/hide-macbook-raop.lua".source = ./hide-macbook-raop.lua;
        "wireplumber/scripts/select-hdmi-combo-profile.lua".source = ./select-hdmi-combo-profile.lua;
      };

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

        "wireplumber/wireplumber.conf.d/99-select-hdmi-combo-profile.conf".text = ''
          wireplumber.components = [
            {
              name = select-hdmi-combo-profile.lua, type = script/lua
              provides = hooks.custom.select-hdmi-combo-profile
            }
          ]

          wireplumber.profiles = {
            main = {
              hooks.custom.select-hdmi-combo-profile = required
            }
          }
        '';

        # The AMD HDMI codec exposes four pins whether or not a display is attached.
        # Opened through UCM, its HiFi profile activates all four at once and carries no
        # port availability, so the empty pins surface as selectable sinks that silently
        # swallow audio. ACP reads the per-pin jack kctls instead, tracking which pins
        # hold a live ELD and updating that on hotplug.
        #
        # The profile set below supplies the combination profiles ACP lacks; see
        # select-hdmi-combo-profile.lua for why one is picked explicitly.
        #
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
                  device.profile-set = "${hdmiComboProfiles}"
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
