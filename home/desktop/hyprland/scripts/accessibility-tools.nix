{
  pkgs,
  lib,
  config,
  ...
}: let
  # Import hyprvoice from our flake packages
  hyprvoice = pkgs.callPackage ../../../../packages/hyprvoice.nix {};

  # Whisper model path (use hyprvoice's downloaded model)
  whisperModelPath = "${config.home.homeDirectory}/.local/share/hyprvoice/models/whisper";
  whisperModel = "small.en";

  # VAD model path
  vadModelPath = "${config.home.homeDirectory}/.local/share/whisper-models/ggml-silero-v6.2.0.bin";

  # Real-time STT with Silero VAD
  # Records audio, uses Silero VAD to detect speech, transcribes with whisper
  stt-stream-start = pkgs.writeShellScriptBin "stt-stream-start" ''
    PIDFILE="/tmp/stt-stream.pid"
    AUDIOFILE="/tmp/stt-audio.wav"

    # Kill any existing stream
    if [[ -f "$PIDFILE" ]]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE"
    fi
    ${pkgs.procps}/bin/pkill -f "stt-vad-loop" 2>/dev/null || true
    ${pkgs.procps}/bin/pkill -f "pw-record.*stt-audio" 2>/dev/null || true

    # Check models exist
    MODEL="${whisperModelPath}/ggml-${whisperModel}.bin"
    VAD_MODEL="${vadModelPath}"
    if [[ ! -f "$MODEL" ]]; then
      ${lib.getExe pkgs.libnotify} -t 5000 "Whisper" "Model not found: $MODEL"
      exit 1
    fi
    if [[ ! -f "$VAD_MODEL" ]]; then
      ${lib.getExe pkgs.libnotify} -t 5000 "Whisper" "VAD model not found: $VAD_MODEL"
      exit 1
    fi

    ${lib.getExe pkgs.libnotify} -t 2000 -r 8888 "🎤 Listening" "Silero VAD active - speak to transcribe"

    # Start the VAD loop in background
    ${pkgs.util-linux}/bin/setsid ${pkgs.bash}/bin/bash -c '
      while true; do
        # Record 4 seconds of audio using ffmpeg (more reliable than pw-record)
        timeout 4 ${pkgs.ffmpeg}/bin/ffmpeg -f pulse -i default -ar 16000 -ac 1 -y "'"$AUDIOFILE"'" 2>/dev/null

        # Transcribe with Silero VAD (only processes speech segments)
        RESULT=$(${pkgs.whisper-cpp-vulkan}/bin/whisper-cli \
          -m "'"$MODEL"'" \
          -f "'"$AUDIOFILE"'" \
          -l en \
          --no-timestamps \
          --vad \
          --vad-model "'"$VAD_MODEL"'" \
          --vad-threshold 0.5 \
          2>/dev/null | \
          ${pkgs.gnused}/bin/sed "s/^[[:space:]]*//;s/[[:space:]]*$//" | \
          ${pkgs.gnugrep}/bin/grep -v "^\[" | \
          ${pkgs.gnugrep}/bin/grep -v "^(" | \
          ${pkgs.gnugrep}/bin/grep -v "^$" | \
          tr -d "\n")

        # Type result if not empty
        if [[ -n "$RESULT" ]]; then
          ${pkgs.wtype}/bin/wtype -- "$RESULT "
        fi

        rm -f "'"$AUDIOFILE"'"
      done
    ' &

    echo $! > "$PIDFILE"
    disown
  '';

  stt-stream-stop = pkgs.writeShellScriptBin "stt-stream-stop" ''
    PIDFILE="/tmp/stt-stream.pid"

    if [[ -f "$PIDFILE" ]]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE"
    fi
    ${pkgs.procps}/bin/pkill -f "stt-vad-loop" 2>/dev/null || true
    ${pkgs.procps}/bin/pkill -f "ffmpeg.*stt-audio" 2>/dev/null || true
    ${pkgs.procps}/bin/pkill -f "whisper-cli.*stt-audio" 2>/dev/null || true

    rm -f /tmp/stt-audio.wav

    ${lib.getExe pkgs.libnotify} -t 1500 -r 8888 "✓ Stopped" "Listening ended"
  '';

  stt-stream-toggle = pkgs.writeShellScriptBin "stt-stream-toggle" ''
    PIDFILE="/tmp/stt-stream.pid"

    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      exec ${stt-stream-stop}/bin/stt-stream-stop
    else
      exec ${stt-stream-start}/bin/stt-stream-start
    fi
  '';
in {
  home.packages = [
    # OCR tool - select area and copy text
    pkgs.normcap

    # Speech-to-text - hyprvoice (batch mode toggle)
    hyprvoice

    # Speech-to-text - whisper-stream (real-time VAD streaming)
    pkgs.whisper-cpp-vulkan
    stt-stream-start
    stt-stream-stop
    stt-stream-toggle

    # Text injection
    pkgs.wtype
    pkgs.wl-clipboard

    # Zoom tool - scroll to zoom, drag to pan
    pkgs.woomer
  ];

  # Hyprvoice configuration
  xdg.configFile."hyprvoice/config.toml".text = ''
    # Hyprvoice configuration
    # Run `hyprvoice configure` to modify via TUI

    [recording]
    sample_rate = 16000
    channels = 1
    format = "s16"
    buffer_size = 8192
    device = ""
    channel_buffer_size = 30
    timeout = "5m"

    [transcription]
    provider = "whisper-cpp"
    model = "small.en"
    language = ""
    streaming = false
    threads = 0

    [injection]
    backends = ["wtype", "clipboard"]
    ydotool_timeout = "5s"
    wtype_timeout = "5s"
    clipboard_timeout = "3s"

    [notifications]
    enabled = true
    type = "desktop"
  '';

  # Hyprvoice systemd user service
  systemd.user.services.hyprvoice = {
    Unit = {
      Description = "Hyprvoice - Voice-powered typing daemon";
      After = ["graphical-session.target" "pipewire.service"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${hyprvoice}/bin/hyprvoice serve";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
