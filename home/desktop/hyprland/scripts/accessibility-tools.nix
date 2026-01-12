{
  pkgs,
  lib,
  config,
  ...
}: let
  # Whisper model to use (small for better quality)
  whisperModel = "small";
  whisperModelPath = "${config.home.homeDirectory}/.local/share/whisper-models";
  whisperPort = "8178";

  # Script to ensure model is downloaded
  ensure-whisper-model = pkgs.writeShellScriptBin "ensure-whisper-model" ''
    #!/usr/bin/env bash
    MODEL_PATH="${whisperModelPath}/ggml-${whisperModel}.bin"

    if [[ ! -f "$MODEL_PATH" ]]; then
      mkdir -p "${whisperModelPath}"
      ${lib.getExe pkgs.libnotify} -t 10000 "Whisper" "Downloading ${whisperModel} model (~500MB)..." || true
      ${pkgs.curl}/bin/curl -L \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${whisperModel}.bin" \
        -o "$MODEL_PATH"
    fi
  '';

  # Toggle-based speech-to-text using whisper-server API
  ptt-toggle = pkgs.writeShellScriptBin "ptt-toggle" ''
    #!/usr/bin/env bash

    PIDFILE="/tmp/ptt-recording.pid"
    AUDIO_FILE="/tmp/ptt-recording.wav"
    SERVER_URL="http://127.0.0.1:${whisperPort}/inference"

    # Kill any zombie processes
    pkill -f "arecord.*ptt-recording" 2>/dev/null || true

    if [[ -f "$PIDFILE" ]]; then
      # STOP recording and transcribe
      PID=$(cat "$PIDFILE")
      kill "$PID" 2>/dev/null || true
      rm -f "$PIDFILE"

      # Wait for file to be written
      sleep 0.2

      # Check if we got audio
      if [[ ! -f "$AUDIO_FILE" ]] || [[ ! -s "$AUDIO_FILE" ]]; then
        ${lib.getExe pkgs.libnotify} -t 2000 "Speech-to-Text" "No audio recorded"
        exit 1
      fi

      ${lib.getExe pkgs.libnotify} -t 1000 "⏳ Transcribing..." ""

      # Transcribe via whisper-server API
      RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST "$SERVER_URL" \
        -F "file=@$AUDIO_FILE" \
        -F "response_format=json" \
        -F "temperature=0.0")

      # Extract text from JSON response
      TEXT=$(echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.text // empty' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      if [[ -n "$TEXT" ]]; then
        # Type using ydotool
        ${pkgs.ydotool}/bin/ydotool type "$TEXT"
        ${lib.getExe pkgs.libnotify} -t 2000 "✓ Typed" "$TEXT"
      else
        # Check if server is running
        if ! ${pkgs.curl}/bin/curl -s "http://127.0.0.1:${whisperPort}/" >/dev/null 2>&1; then
          ${lib.getExe pkgs.libnotify} -t 3000 "Speech-to-Text" "Server not running. Starting..."
          systemctl --user start whisper-server
          sleep 2
          ${lib.getExe pkgs.libnotify} -t 2000 "Speech-to-Text" "Try again"
        else
          ${lib.getExe pkgs.libnotify} -t 2000 "Speech-to-Text" "No speech detected"
        fi
      fi

      # Cleanup
      rm -f "$AUDIO_FILE"

    else
      # START recording
      # Check if server is running, start if not
      if ! ${pkgs.curl}/bin/curl -s "http://127.0.0.1:${whisperPort}/" >/dev/null 2>&1; then
        ${lib.getExe pkgs.libnotify} -t 2000 "Speech-to-Text" "Starting whisper server..."
        systemctl --user start whisper-server
        sleep 3
      fi

      ${lib.getExe pkgs.libnotify} -t 3000 "🎤 Recording..." "Press again to stop and transcribe"

      # Record audio in background
      ${pkgs.alsa-utils}/bin/arecord -f S16_LE -r 16000 -c 1 -t wav "$AUDIO_FILE" 2>/dev/null &
      echo $! > "$PIDFILE"
    fi
  '';
in {
  home.packages = [
    # OCR tool
    pkgs.normcap

    # Speech-to-text (Vulkan for AMD GPU acceleration)
    pkgs.whisper-cpp-vulkan
    pkgs.alsa-utils
    pkgs.curl
    pkgs.jq
    pkgs.ydotool
    ptt-toggle
    ensure-whisper-model

    # Zoom tool (woomer - smooth zoom with mouse control)
    pkgs.woomer
  ];

  # Whisper server systemd service
  systemd.user.services.whisper-server = {
    Unit = {
      Description = "Whisper.cpp Speech-to-Text Server";
      After = ["network.target"];
    };
    Service = {
      Type = "simple";
      ExecStartPre = "${ensure-whisper-model}/bin/ensure-whisper-model";
      ExecStart = "${pkgs.whisper-cpp-vulkan}/bin/whisper-server -m ${whisperModelPath}/ggml-${whisperModel}.bin --host 127.0.0.1 --port ${whisperPort} -l en --no-timestamps";
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };
}
