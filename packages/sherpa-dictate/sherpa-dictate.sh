# shellcheck shell=bash
# Prepended by default.nix, which supplies the shebang along with
# VAD_MODEL, MODEL_DIR, DEVICE, GEMINI_URL, PHRASE_PAUSE and PHRASE_MIN.

runtime="${XDG_RUNTIME_DIR:-/tmp}/sherpa-dictate"
pidfile="$runtime/pid"

# auto picks gemini only when the adapter URL is configured; asking for gemini
# without it is an error rather than a silent downgrade to the local model.
resolve_mode() {
  case "${SHERPA_DICTATE_MODE:-auto}" in
  gemini) echo gemini ;;
  local) echo local ;;
  *) if [ -n "$GEMINI_URL" ]; then echo gemini; else echo local; fi ;;
  esac
}

running() {
  [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

# sherpa-onnx writes transcripts to STDERR, not stdout, so the pipe has to
# carry 2>&1 — stdout alone is empty. tee keeps the full stream (including the
# config dump) for diagnosis.
#
# Each committed utterance is numbered, " 0: some words." — note that is NOT
# the "<start> -- <end>: <text>" the file-based sherpa-onnx-vad-with-offline-asr
# emits. Anchoring on the index keeps chatter ("Use recording device:
# plug:default") out of the typed stream. stdbuf keeps both stages
# line-buffered, otherwise nothing types until 4KB accumulates.
#
# The sed stage drops filler words, the same list voxtype filters, and
# re-capitalizes a segment that opened with one. It runs after tee so the log
# keeps the raw transcript. A segment that was nothing but filler leaves bare
# punctuation, which the alnum check refuses to type.
filler_words='uh|um|er|ah|eh|hmm|hm|mm|mhm'
fillers="($filler_words)"

listen() {
  if [ "$(resolve_mode)" = gemini ]; then
    # exec keeps the pidfile on the python process; it prints "Please speak"
    # once capture is open, which start() polls for.
    exec voxtype-gemini-phrases --url "$GEMINI_URL" --pause "$PHRASE_PAUSE" \
      --min-phrase "$PHRASE_MIN" --local-model-dir "$MODEL_DIR" \
      --vad-model "$VAD_MODEL" --device "$DEVICE" --fillers "$filler_words" \
      >"$runtime/log" 2>&1
  fi
  stdbuf -oL sherpa-onnx-vad-alsa-offline-asr \
    --silero-vad-model="$VAD_MODEL" \
    --encoder="$MODEL_DIR/encoder.int8.onnx" \
    --decoder="$MODEL_DIR/decoder.int8.onnx" \
    --joiner="$MODEL_DIR/joiner.int8.onnx" \
    --tokens="$MODEL_DIR/tokens.txt" \
    --num-threads=4 \
    "$DEVICE" 2>&1 |
    stdbuf -oL tee "$runtime/log" |
    sed -uE \
      -e "s/^([[:space:]]*[0-9]+:[[:space:]]?)$fillers\\b[,.]?[[:space:]]*([a-z])/\\1\\u\\3/I" \
      -e "s/\\b$fillers\\b,?//gI" \
      -e 's/[[:space:],]+([.?!])/\1/g' \
      -e 's/  +/ /g' |
    while IFS= read -r line; do
      [[ $line =~ ^[[:space:]]*[0-9]+:[[:space:]]?(.*)$ ]] || continue
      text="${BASH_REMATCH[1]}"
      [[ $text =~ [[:alnum:]] ]] && wtype -- "$text "
    done
}

start() {
  running && return 0
  if [ "${SHERPA_DICTATE_MODE:-auto}" = gemini ] && [ -z "$GEMINI_URL" ]; then
    notify-send -t 3000 -r 9042 "Dictation" "Gemini mode needs the adapter enabled"
    exit 1
  fi
  mkdir -p "$runtime"
  # stop() clears the pidfile at once, so a second press during the drain would
  # otherwise enter start() too. A press that finds the lock held cancels the
  # pending start instead. A press in the instant after the holder's last cancel
  # check and before the pidfile write is not caught.
  exec 9>"$runtime/start.lock"
  if ! flock -n 9; then
    touch "$runtime/start.cancel"
    notify-send -t 2000 -r 9042 "Dictation" "Cancelled"
    return 0
  fi
  rm -f "$runtime/start.cancel"
  running && return 0
  # A stop during the Gemini drain leaves the old group typing its last
  # phrases; starting beside it would interleave and reorder text.
  if [ -f "$runtime/draining" ]; then
    # A leftover file whose pid was reused would stall the wait on an
    # unrelated group.
    if [ $(($(date +%s) - $(stat -c %Y "$runtime/draining"))) -gt 15 ]; then
      rm -f "$runtime/draining"
    else
      old=$(cat "$runtime/draining")
      if kill -0 -- -"$old" 2>/dev/null; then
        notify-send -t 2000 -r 9042 "Dictation" "Finishing previous phrases…"
        for _ in $(seq 100); do
          if [ -f "$runtime/start.cancel" ]; then
            rm -f "$runtime/start.cancel"
            exec 9>&-
            return 0
          fi
          kill -0 -- -"$old" 2>/dev/null || break
          sleep 0.1
        done
        kill -KILL -- -"$old" 2>/dev/null || true
      fi
      rm -f "$runtime/draining"
    fi
  fi
  if [ -f "$runtime/start.cancel" ]; then
    rm -f "$runtime/start.cancel"
    exec 9>&-
    return 0
  fi
  : >"$runtime/log"
  setsid "$0" __listen 9>&- &
  echo $! >"$pidfile"
  # stop() must signal the way this listener was started, not the way the
  # stop call's environment would resolve.
  resolve_mode >"$runtime/mode"
  exec 9>&-

  # Loading Parakeet takes ~3s, and announcing "listening" before the
  # recognizer exists invites talking into a mic that is not capturing yet.
  # Claim it only once the ASR says so; the shared -r id replaces the first
  # toast rather than stacking.
  notify-send -t 4000 -r 9042 "Dictation" "Starting…"
  (
    for _ in $(seq 100); do
      if grep -q "Please speak" "$runtime/log" 2>/dev/null; then
        notify-send -t 2000 -r 9042 "Dictation" "Listening — speak, pause to commit"
        exit 0
      fi
      sleep 0.1
    done
    notify-send -t 3000 -r 9042 "Dictation" "Failed to start — see $runtime/log"
  ) &
}

stop() {
  if running; then
    pid=$(cat "$pidfile")
    mode=$(cat "$runtime/mode" 2>/dev/null || true)
    if [ "$mode" = gemini ]; then
      # The CLI ends its own arecord on SIGTERM and then drains queued phrases;
      # a group signal would also kill a wtype that is mid-type.
      echo "$pid" >"$runtime/draining"
      kill "$pid" 2>/dev/null || true
    else
      # setsid made the child a group leader; kill the group so the ASR process
      # and the wtype reader both go down.
      kill -- -"$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile" "$runtime/mode"
  notify-send -t 1500 -r 9042 "Dictation" "Stopped"
}

case "${1:-toggle}" in
start) start ;;
stop) stop ;;
toggle) if running; then stop; else start; fi ;;
status)
  running && echo listening || echo stopped
  ;;
mode) resolve_mode ;;
__listen) listen ;;
*)
  echo "usage: sherpa-dictate [start|stop|toggle|status|mode]" >&2
  exit 1
  ;;
esac
