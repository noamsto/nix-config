# Workaround for https://github.com/anthropics/claude-code/issues/9935
# PTY proxy that tames Claude Code's massive terminal updates using VT-based rendering
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "claude-chill";
  version = "0.1.0-unstable-2025-01-20";

  src = fetchFromGitHub {
    owner = "davidbeesley";
    repo = "claude-chill";
    rev = "35ecc80e2f6e5fca2ea31252b28e69422e303bbf";
    hash = "sha256-mY7QXl9yDrZ5KNqZjaQGlBIAnrHoJdHvwWb/P4BzENg=";
  };

  cargoHash = "sha256-q906Fv+tXo3F05OvQh8qU7teYq7OkEdYmO3pdOwHWdo=";

  meta = with lib; {
    description = "PTY proxy that reduces Claude Code terminal flicker using VT-based rendering";
    longDescription = ''
      claude-chill sits between your terminal and Claude Code, intercepting
      synchronized output blocks and rendering only the differences using a
      VT100 emulator. This fixes the excessive scroll events (4,000-6,700/sec)
      that cause UI jitter in terminal multiplexers like tmux.
    '';
    homepage = "https://github.com/davidbeesley/claude-chill";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "claude-chill";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
