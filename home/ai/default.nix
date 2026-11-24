{applyKeyed, ...}: {
  imports = [
    (applyKeyed ./agent-skills)
    ../checkout-check.nix
    ./amp
    (applyKeyed ./claude-code)
    (applyKeyed ./cursor)
    (applyKeyed ./deja-vu)
    (applyKeyed ./forged)
    (applyKeyed ./hookyard)
    (applyKeyed ./houston)
    ./mcp.nix
    (applyKeyed ./pi)
    ./priors
  ];
}
