# Sink and user-facing source node ids for one card, plus its current profile index.
# Input: pw-dump array. Arg: $dev = device id.
def on_dev: select((.info.props["device.id"]? | tostring) == ($dev | tostring));

. as $all
| {sink: ([$all[] | select(.info.props["media.class"]? == "Audio/Sink") | on_dev | .id][0]),
   source: ([$all[] | select(.info.props["media.class"]? == "Audio/Source") | on_dev
             | select(.info.props["api.bluez5.internal"]? != true)]
            | (map(select(.info.props["bluez5.loopback"] == true)) + .)[0].id),
   profile: ([$all[] | select(.type == "PipeWire:Interface:Device" and (.id | tostring) == ($dev | tostring))
              | .info.params.Profile[0].index][0])}
