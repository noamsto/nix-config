# VAD_MODEL, MODEL_DIR and DEVICE are injected by default.nix.

runtime="${XDG_RUNTIME_DIR:-/tmp}/sherpa-dictate"
pidfile="$runtime/pid"

running() {
  [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

# Each committed utterance arrives as "<start> -- <end>: <text>"; every other
# line is model/config chatter. stdbuf keeps the pipe line-buffered, otherwise
# nothing types until 4KB of output accumulates.
listen() {
  stdbuf -oL sherpa-onnx-vad-alsa-offline-asr \
    --silero-vad-model="$VAD_MODEL" \
    --encoder="$MODEL_DIR/encoder.int8.onnx" \
    --decoder="$MODEL_DIR/decoder.int8.onnx" \
    --joiner="$MODEL_DIR/joiner.int8.onnx" \
    --tokens="$MODEL_DIR/tokens.txt" \
    --num-threads=4 \
    "$DEVICE" 2>/dev/null |
    while IFS= read -r line; do
      case "$line" in
      *' -- '*': '*) text="${line#*: }" ;;
      *) continue ;;
      esac
      [ -n "$text" ] && wtype -- "$text "
    done
}

start() {
  running && return 0
  mkdir -p "$runtime"
  setsid "$0" __listen &
  echo $! >"$pidfile"
  notify-send -t 2000 -r 9042 "Dictation" "Listening — speak, pause to commit"
}

stop() {
  if running; then
    # setsid made the child a group leader; kill the group so the ASR process
    # and the wtype reader both go down.
    kill -- -"$(cat "$pidfile")" 2>/dev/null || true
  fi
  rm -f "$pidfile"
  notify-send -t 1500 -r 9042 "Dictation" "Stopped"
}

case "${1:-toggle}" in
start) start ;;
stop) stop ;;
toggle) if running; then stop; else start; fi ;;
status)
  running && echo listening || echo stopped
  ;;
__listen) listen ;;
*)
  echo "usage: sherpa-dictate [start|stop|toggle|status]" >&2
  exit 1
  ;;
esac
