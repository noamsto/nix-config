{applyKeyed, ...}: {
  imports = [
    (applyKeyed ./agent-skills)
    ./amp
    (applyKeyed ./claude-code)
    (applyKeyed ./cursor)
    (applyKeyed ./deja-vu)
    (applyKeyed ./hookyard)
    (applyKeyed ./houston)
    ./mcp.nix
    (applyKeyed ./pi)
    ./priors
  ];
}
