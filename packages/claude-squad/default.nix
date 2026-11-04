{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  tmux,
  gh,
  git,
}:
buildGoModule rec {
  pname = "claude-squad";
  version = "1.0.13";

  src = fetchFromGitHub {
    owner = "smtg-ai";
    repo = "claude-squad";
    rev = "v${version}";
    hash = "sha256-OL+IG+NvrwAc0+7BlKJPKdSx8ZIbI/FtdvlAA807NYI=";
  };

  vendorHash = "sha256-BduH6Vu+p5iFe1N5svZRsb9QuFlhf7usBjMsOtRn2nQ=";

  # Skip tests - they require git in PATH during check phase
  doCheck = false;

  # Build from root directory (main.go is at project root)
  subPackages = ["."];

  nativeBuildInputs = [makeWrapper];

  # Runtime dependencies
  buildInputs = [
    tmux
    gh
  ];

  # Wrap binary to ensure tmux, gh, and git are in PATH
  postInstall = ''
    wrapProgram $out/bin/claude-squad \
      --prefix PATH : ${lib.makeBinPath [tmux gh git]}

    # Create cs symlink for shorter command
    ln -s $out/bin/claude-squad $out/bin/cs
  '';

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "Terminal TUI for orchestrating multiple AI coding agents with isolated git worktrees";
    longDescription = ''
      Claude Squad manages multiple AI agents (Claude Code, Aider, Codex, Gemini)
      simultaneously in separate tmux sessions with isolated git worktrees.
      Features include parallel task execution, change review, and unified management interface.
    '';
    homepage = "https://github.com/smtg-ai/claude-squad";
    license = licenses.agpl3Only;
    maintainers = [];
    mainProgram = "cs";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
