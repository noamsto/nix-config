{lib, ...}: let
  # Public, non-fork repos under github.com/noamsto.
  ossRepos = [
    "aegis-lock"
    "aeye"
    "agent-smith"
    "dispatcher"
    "houston"
    "lazytmux"
    "mermaid2d2"
    "nix-amd-ai"
    "noamsto"
    "noctalia-plugin-keep-awake"
    "octo-ai.nvim"
    "prdash"
    "resolved"
    "resolved.nvim"
    "rss_simulator_nvidia"
    "stole.ro"
    "themestate"
    "tmux-remux"
    "una-nix"
    "wtc"
    "zr"
  ];
in {
  # Section paths are relative to the dir holding .mrconfig, and programs.mr
  # writes it to $HOME — hence the "git/" prefix rather than an absolute path.
  programs.mr = {
    enable = true;
    settings = lib.listToAttrs (map (name: {
        name = "git/${name}";
        value.checkout = "git clone ssh://git@github.com/noamsto/${name}.git ${name}";
      })
      ossRepos);
  };
}
