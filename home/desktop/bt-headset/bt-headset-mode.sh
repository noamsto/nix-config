# shellcheck shell=bash
usage() {
  echo "Usage: bt-headset-mode call|music|toggle|status" >&2
  exit 2
}

# Vicinae shows only the first stdout line, so user-facing errors go there.
fail() {
  echo "$1"
  exit 1
}

[ "$#" -eq 1 ] || usage
case "$1" in
call | music | toggle | status) ;;
*) usage ;;
esac

plan=$(pw-dump | jq --arg mode "$1" -f @planJq@)

case "$(jq -r '.error // ""' <<<"$plan")" in
no-device)
  fail "No Bluetooth audio device connected."
  ;;
no-profile)
  fail "$(jq -r '.device.description' <<<"$plan") offers no $(jq -r '.mode' <<<"$plan") profile."
  ;;
esac

mode=$(jq -r '.mode' <<<"$plan")
dev=$(jq -r '.device.id' <<<"$plan")
desc=$(jq -r '.device.description' <<<"$plan")
count=$(jq -r '.count' <<<"$plan")

if [ "$count" -gt 1 ]; then
  echo "Using $desc ($count Bluetooth audio devices connected)" >&2
fi

if [ "$mode" = status ]; then
  jq -r '"\(.device.description): \(.current.name) (\(.current.description))"' <<<"$plan"
  exit 0
fi

target_index=$(jq -r '.target.index' <<<"$plan")
target_name=$(jq -r '.target.name' <<<"$plan")
target_desc=$(jq -r '.target.description' <<<"$plan")

device_nodes() {
  pw-dump | jq -c --argjson dev "$dev" -f @nodesJq@
}

if [ "$(jq -r '.current.index' <<<"$plan")" != "$target_index" ]; then
  wpctl set-profile "$dev" "$target_index"
fi

nodes=
for _ in $(seq 20); do
  nodes=$(device_nodes)
  if jq -e --argjson t "$target_index" --arg mode "$mode" \
    '.profile == $t and .sink != null and (.source != null or $mode != "call")' <<<"$nodes" >/dev/null; then
    break
  fi
  nodes=
  sleep 0.25
done

if [ -z "$nodes" ]; then
  notify-send -u critical "Headset: switch failed" "$desc did not reach $target_name" || true
  fail "$desc did not reach $target_name"
fi

wpctl set-default "$(jq -r '.sink' <<<"$nodes")"
if [ "$mode" = call ]; then
  wpctl set-default "$(jq -r '.source' <<<"$nodes")"
fi

# WirePlumber's autoswitch restores A2DP ~2s after nothing captures the
# headset mic, and flips back to HFP as soon as something does.
sleep 2.5
final=$(device_nodes | jq -r '.profile')

if [ "$final" = null ]; then
  notify-send -u critical "Headset: switch failed" "$desc disconnected" || true
  fail "$desc disconnected"
fi

if [ "$final" = "$target_index" ]; then
  body="$desc — $target_desc"
elif [ "$mode" = call ]; then
  body="$desc: mic set as default input; WirePlumber keeps music mode until an app records"
else
  body="$desc: an app is recording from the headset, so WirePlumber switched back to call mode"
fi

if [ "$mode" = call ]; then
  title="Headset: Call mode"
else
  title="Headset: Music mode"
fi

notify-send "$title" "$body"
echo "$title: $body"
