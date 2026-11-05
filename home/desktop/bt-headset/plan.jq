# Pick the Bluetooth card to act on and the profile to switch it to.
# Input: pw-dump array. Arg: $mode = call|music|toggle|status.
def call_re: "^(headset-head-unit|bap-duplex)";
def music_re: "^(a2dp-sink|a2dp-duplex|bap-sink)";

. as $all
| [$all[] | select(.type == "PipeWire:Interface:Device" and .info.props["device.api"]? == "bluez5")] | sort_by(.id) as $bt
| if ($bt | length) == 0 then {error: "no-device"}
  else
    ([$all[] | select(.props["metadata.name"]? == "default") | .metadata[]?
      | select(.key == "default.audio.sink") | .value.name][0]) as $sink_name
    | ([$all[] | select(.info.props["node.name"]? == $sink_name and $sink_name != null)
        | .info.props["device.id"] | tostring][0]) as $sink_dev
    | ([$bt[] | select((.id | tostring) == $sink_dev)][0] // $bt[0]) as $dev
    | ($dev.info.params.Profile[0] // null) as $current
    | (if $mode == "toggle"
       then (if ($current.name? // "") | test(call_re) then "music" else "call" end)
       else $mode end) as $m
    | {id: $dev.id,
       name: $dev.info.props["device.name"],
       description: $dev.info.props["device.description"]} as $device
    | if $m == "status"
      then {count: ($bt | length), mode: "status", device: $device, current: $current, target: null}
      else
        ([$dev.info.params.EnumProfile[]?
          | select(.available != "no" and (.name | test(if $m == "call" then call_re else music_re end)))]
         | max_by(.priority)) as $target
        | if $target == null
          then {error: "no-profile", count: ($bt | length), device: $device, mode: $m}
          else {count: ($bt | length), mode: $m, device: $device, current: $current, target: $target}
          end
      end
  end
