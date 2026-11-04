-- Keep the AMD HDMI card on the profile whose sinks are exactly the live pins.
--
-- ACP publishes one route per HDMI pin and marks it available only while that
-- pin reports a live ELD, refreshing on hotplug. It ships no combination
-- profile for this card, so on its own it can expose only one HDMI output at a
-- time. The generated profile set adds one combination profile per subset of
-- pins; this hook activates the subset whose routes are currently available.
--
-- The selection has to be explicit because ACP derives a combination profile's
-- availability as an OR over its mappings: a combo holding one live and one
-- dead pin still reports "available", so find-best-profile cannot tell it apart
-- from the all-live one and would leave dead pins publishing silent sinks.
--
-- Route *names* are the stable key here. A route keeps its hdmi-output-N name
-- across profile switches, while the device indices it lists are renumbered per
-- profile, and every pin's route stays enumerated even when the active profile
-- excludes it -- which is what lets a newly plugged monitor be noticed at all.
cutils = require("common-utils")
log = Log.open_topic("s-select-hdmi-combo-profile")

local CARD = "Radeon High Definition Audio Controller"

local function live_pins(device)
  local pins = {}
  for p in device:iterate_params("EnumRoute") do
    local route = cutils.parseParam(p, "EnumRoute")
    if route and route.available == "yes" then
      local pin = tostring(route.name):match("^hdmi%-output%-(%d+)$")
      if pin then
        pins[#pins + 1] = tonumber(pin)
      end
    end
  end
  table.sort(pins)
  return pins
end

-- Pin availability changes on monitor hotplug; re-run the selection chain.
SimpleEventHook {
  name = "device/rescan-hdmi-combo-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "EnumRoute" },
    },
  },
  execute = function (event)
    local device = event:get_subject()
    if device.properties["device.product.name"] ~= CARD then
      return
    end
    event:get_source():call("push-event", "select-profile", device, nil)
  end,
}:register()

SimpleEventHook {
  name = "device/select-hdmi-combo-profile",
  before = "device/find-stored-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    local device = event:get_subject()
    if device.properties["device.product.name"] ~= CARD then
      return
    end

    local pins = live_pins(device)
    local wanted = "off"
    if #pins > 0 then
      wanted = "output:hdmi-combo-" .. table.concat(pins, "-")
    end

    for p in device:iterate_params("EnumProfile") do
      local profile = cutils.parseParam(p, "EnumProfile")
      if profile and profile.name == wanted then
        log:info(device, "live HDMI pins -> profile " .. wanted)
        event:set_data("selected-profile", profile)
        return
      end
    end
    log:warning(device, "no profile named " .. wanted)
  end,
}:register()
