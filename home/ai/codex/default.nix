{pkgs, ...}: {
  # OpenAI Codex CLI. Used both interactively and as an alternate `dispatch`
  # worker engine (`dispatch … --agent codex …`). Auth is out of band — run
  # `codex login` once; there's no secret to manage in Nix.
  home.packages = [pkgs.codex];
}
