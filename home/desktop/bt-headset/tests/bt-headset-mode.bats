#!/usr/bin/env bats
# Regression suite for the bt-headset-mode jq filters (plan.jq, nodes.jq) and
# the script control flow, run against stubbed pw-dump/wpctl/notify-send.
#
# Run: nix build .#checks.x86_64-linux.bt-headset-mode

bats_require_minimum_version 1.5.0

setup() {
  PLAN=${BT_PLAN_JQ:?BT_PLAN_JQ must be set}
  NODES=${BT_NODES_JQ:?BT_NODES_JQ must be set}
  BASE=${FIXTURE:?FIXTURE must be set}
  SCRIPT=${BT_SCRIPT:?BT_SCRIPT must be set}
}

plan() { # <mode> [fixture]
  jq -c --arg mode "$1" -f "$PLAN" <"${2:-$BASE}"
}

plan_field() { # <mode> <jq path> [fixture]
  plan "$1" "${3:-}" | jq -r "$2"
}

nodes() { # <dev> [fixture]
  jq -c --argjson dev "$1" -f "$NODES" <"${2:-$BASE}"
}

# Variant fixture: apply a jq expression to the base fixture.
variant() { # <name> <jq expr>
  jq -c "$2" "$BASE" >"$BATS_TEST_TMPDIR/$1.json"
  echo "$BATS_TEST_TMPDIR/$1.json"
}

@test "picks the card backing the default sink and counts both" {
  [ "$(plan_field status .device.id)" = 95 ]
  [ "$(plan_field status .count)" = 2 ]
  [ "$(plan_field status .device.name)" = bluez_card.22_22_22_22_22_22 ]
  [ "$(plan_field status .device.description)" = "Jabra Evolve" ]
}

@test "non-BT default sink falls back to the first BT card by id" {
  f=$(variant nonbt '(.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[0].value.name) = "alsa_output.usb-Microsoft_LifeCam.analog-stereo"')
  [ "$(plan_field status .device.id "$f")" = 90 ]
  [ "$(plan_field status .count "$f")" = 2 ]
}

@test "string device.id on the default sink node still resolves its card" {
  f=$(variant strid '(.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[0].value.name) = "bluez_output.11_11_11_11_11_11.1"')
  [ "$(plan_field status .device.id "$f")" = 90 ]
}

@test "call picks the best available headset profile" {
  f=$(variant nonbt '(.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[0].value.name) = "alsa_output.usb-Microsoft_LifeCam.analog-stereo"')
  [ "$(plan_field call .mode "$f")" = call ]
  [ "$(plan_field call .target.name "$f")" = headset-head-unit ]
  [ "$(plan_field call .target.index "$f")" = 5 ]
}

@test "music picks the highest-priority A2DP profile" {
  f=$(variant nonbt '(.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[0].value.name) = "alsa_output.usb-Microsoft_LifeCam.analog-stereo"')
  [ "$(plan_field music .mode "$f")" = music ]
  [ "$(plan_field music .target.name "$f")" = a2dp-sink ]
  [ "$(plan_field music .target.priority "$f")" = 131 ]
}

@test "toggle flips headset to music and a2dp to call" {
  [ "$(plan_field toggle .mode)" = music ]
  [ "$(plan_field toggle .target.name)" = a2dp-sink ]
  [ "$(plan_field toggle .target.index)" = 1 ]
  f=$(variant nonbt '(.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[0].value.name) = "alsa_output.usb-Microsoft_LifeCam.analog-stereo"')
  [ "$(plan_field toggle .mode "$f")" = call ]
  [ "$(plan_field toggle .target.name "$f")" = headset-head-unit ]
}

@test "status returns the current profile and a null target" {
  [ "$(plan_field status .mode)" = status ]
  [ "$(plan_field status .current.name)" = headset-head-unit ]
  [ "$(plan_field status .target)" = null ]
  [ "$(plan_field status 'has("error")')" = false ]
}

@test "no bluez device yields no-device" {
  f=$(variant nobt 'map(select(.info.props["device.api"] != "bluez5"))')
  [ "$(plan_field call .error "$f")" = no-device ]
  [ "$(plan_field status .error "$f")" = no-device ]
}

@test "a bluez5 node without a bluez5 device (MIDI bridge) is not a device" {
  f=$(variant midi '
    map(select(.info.props["device.api"] != "bluez5"))
    + [{"id":66,"type":"PipeWire:Interface:Node",
        "info":{"props":{"device.api":"bluez5","node.name":"bluez_midi.server","media.class":"Midi/Bridge"}}}]')
  [ "$(plan_field status .error "$f")" = no-device ]
}

@test "a2dp-duplex-only device: music picks it" {
  f=$(variant duplex '
    (.[] | select(.id == 95) | .info.params) |= (
      .EnumProfile = [
        {"index":0,"name":"off","description":"Off","priority":0,"available":"yes","classes":[]},
        {"index":1,"name":"a2dp-duplex","description":"High Fidelity Duplex","priority":129,"available":"yes","classes":[]}
      ]
      | .Profile = [.EnumProfile[1]])')
  [ "$(plan_field music .target.name "$f")" = a2dp-duplex ]
  [ "$(plan_field music .device.id "$f")" = 95 ]
}

@test "call on a device without HFP yields no-profile" {
  f=$(variant nohfp '
    (.[] | select(.id == 95) | .info.params.EnumProfile) |= map(select(.name | test("^headset") | not))')
  [ "$(plan_field call .error "$f")" = no-profile ]
  [ "$(plan_field call .device.id "$f")" = 95 ]
  [ "$(plan_field call .count "$f")" = 2 ]
  [ "$(plan_field call .mode "$f")" = call ]
}

@test "unavailable headset profile is never chosen" {
  f=$(variant onlyunavail '
    (.[] | select(.id == 90) | .info.params.EnumProfile) |= map(select(.name | test("^headset") | not) )
    | (.[] | select(.id == 90) | .info.params.EnumProfile) += [{"index":6,"name":"headset-head-unit-lc3_swb","description":"x","priority":3,"available":"no","classes":[]}]
    | (.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[0].value.name) = "alsa_output.usb-Microsoft_LifeCam.analog-stereo"')
  [ "$(plan_field call .error "$f")" = no-profile ]
}

@test "nodes: dev 95 gives sink, loopback source (not internal) and profile" {
  [ "$(nodes 95)" = '{"sink":110,"source":111,"profile":2}' ]
}

@test "nodes: dev 90 matches string device.id and reports its profile" {
  [ "$(nodes 90)" = '{"sink":120,"source":121,"profile":1}' ]
}

@test "nodes: absent sink/source are null" {
  f=$(variant nosrc 'map(select(.id != 121 and .id != 120))')
  [ "$(nodes 90 "$f")" = '{"sink":null,"source":null,"profile":1}' ]
}

@test "nodes: falls back to a non-loopback source, never the internal one" {
  f=$(variant noloop 'map(select(.id != 111))')
  [ "$(nodes 95 "$f")" = '{"sink":110,"source":null,"profile":2}' ]
}

# --- script-level tests: stubbed pw-dump / wpctl / notify-send / sleep ---

# Stubs share $STATE, a JSON object {"<dev id>": <profile index> | "gone"}
# that overrides the fixture. `wpctl set-profile` writes it; the 2.5s sleep
# merges $BT_SIM_SETTLE into it to simulate WirePlumber reverting a profile
# or the headset dropping off. BT_NOOP_SET=1 makes set-profile a no-op.
write_stub() { # <name> (body on stdin)
  { echo "#!$BASH"; cat; } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

stub_setup() { # [fixture]
  STUBS=$BATS_TEST_TMPDIR/stubs
  STATE=$BATS_TEST_TMPDIR/state.json
  WPCTL_LOG=$BATS_TEST_TMPDIR/wpctl.log
  NOTIFY_LOG=$BATS_TEST_TMPDIR/notify.log
  mkdir -p "$STUBS"
  echo '{}' >"$STATE"
  : >"$WPCTL_LOG"
  : >"$NOTIFY_LOG"
  export STUB_FIXTURE=${1:-$BASE} STATE WPCTL_LOG NOTIFY_LOG

  write_stub pw-dump <<'EOF'
jq --slurpfile st "$STATE" '
  $st[0] as $s
  | map(select($s[(.id | tostring)] != "gone"))
  | map(if $s[(.id | tostring)] != null
        then $s[(.id | tostring)] as $i
          | .info.params.Profile = [.info.params.EnumProfile[] | select(.index == $i)]
        else . end)' "$STUB_FIXTURE"
EOF
  write_stub wpctl <<'EOF'
echo "$*" >>"$WPCTL_LOG"
if [ "$1" = set-profile ] && [ -z "${BT_NOOP_SET:-}" ]; then
  jq --arg d "$2" --argjson i "$3" '.[$d] = $i' "$STATE" >"$STATE.new"
  mv "$STATE.new" "$STATE"
fi
EOF
  write_stub notify-send <<'EOF'
echo "$*" >>"$NOTIFY_LOG"
EOF
  write_stub sleep <<'EOF'
if [ "$1" = 2.5 ] && [ -n "${BT_SIM_SETTLE:-}" ]; then
  jq --argjson m "$BT_SIM_SETTLE" '. + $m' "$STATE" >"$STATE.new"
  mv "$STATE.new" "$STATE"
fi
EOF

  sed -e "s|@planJq@|$PLAN|" -e "s|@nodesJq@|$NODES|" "$SCRIPT" >"$BATS_TEST_TMPDIR/script.sh"
}

run_script() { # <args...>
  PATH=$STUBS:$PATH run --separate-stderr bash -euo pipefail "$BATS_TEST_TMPDIR/script.sh" "$@"
}

# Variant fixture whose default sink is card 90's (WH-1000XM4).
xm4_default() {
  variant xm4 '(.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[0].value.name) = "bluez_output.11_11_11_11_11_11.1"'
}

@test "script: music switches the card to A2DP and sets the default sink" {
  stub_setup
  run_script music
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$WPCTL_LOG")" = "set-profile 95 1" ]
  [ "$(sed -n 2p "$WPCTL_LOG")" = "set-default 110" ]
  [ "$(wc -l <"$WPCTL_LOG")" -eq 2 ]
  [[ "$output" == "Headset: Music mode: Jabra Evolve — "* ]]
  [ "$stderr" = "Using Jabra Evolve (2 Bluetooth audio devices connected)" ]
}

@test "script: call switches to HFP and sets default sink and source" {
  stub_setup "$(xm4_default)"
  run_script call
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$WPCTL_LOG")" = "set-profile 90 5" ]
  [ "$(sed -n 2p "$WPCTL_LOG")" = "set-default 120" ]
  [ "$(sed -n 3p "$WPCTL_LOG")" = "set-default 121" ]
  [[ "$output" == "Headset: Call mode: WH-1000XM4 — "* ]]
}

@test "script: already on the target profile skips set-profile" {
  stub_setup
  run_script call
  [ "$status" -eq 0 ]
  ! grep -q set-profile "$WPCTL_LOG"
  grep -qx "set-default 110" "$WPCTL_LOG"
  grep -qx "set-default 111" "$WPCTL_LOG"
}

@test "script: call reverted after the settle reports the revert" {
  stub_setup "$(xm4_default)"
  BT_SIM_SETTLE='{"90":1}' run_script call
  [ "$status" -eq 0 ]
  [[ "$output" == "Headset: Call mode: WH-1000XM4: mic set as default input;"* ]]
}

@test "script: music reverted after the settle reports the recording app" {
  stub_setup
  BT_SIM_SETTLE='{"95":2}' run_script music
  [ "$status" -eq 0 ]
  [[ "$output" == "Headset: Music mode: Jabra Evolve: an app is recording"* ]]
}

@test "script: headset gone after the settle fails with a disconnected message" {
  stub_setup
  BT_SIM_SETTLE='{"95":"gone"}' run_script music
  [ "$status" -eq 1 ]
  [ "$output" = "Jabra Evolve disconnected" ]
  grep -q -- "-u critical" "$NOTIFY_LOG"
  grep -q "Jabra Evolve disconnected" "$NOTIFY_LOG"
}

@test "script: no Bluetooth device fails on stdout without touching wpctl" {
  stub_setup "$(variant nobt 'map(select(.info.props["device.api"] != "bluez5"))')"
  run_script music
  [ "$status" -eq 1 ]
  [ "$output" = "No Bluetooth audio device connected." ]
  [ ! -s "$WPCTL_LOG" ]
}

@test "script: no matching profile fails on stdout" {
  stub_setup "$(variant nohfp '(.[] | select(.id == 95) | .info.params.EnumProfile) |= map(select(.name | test("^headset") | not))')"
  run_script call
  [ "$status" -eq 1 ]
  [ "$output" = "Jabra Evolve offers no call profile." ]
  [ ! -s "$WPCTL_LOG" ]
}

@test "script: never reaching the target fails on stdout and notifies critically" {
  stub_setup
  BT_NOOP_SET=1 run_script music
  [ "$status" -eq 1 ]
  [ "$output" = "Jabra Evolve did not reach a2dp-sink" ]
  grep -q -- "-u critical" "$NOTIFY_LOG"
  ! grep -q set-default "$WPCTL_LOG"
}

@test "script: bad arguments print usage on stderr and exit 2" {
  stub_setup
  run_script bogus
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == Usage:* ]]
  run_script
  [ "$status" -eq 2 ]
}
