# Runs the example host's generated nvim config headless in the build sandbox
# (no network) with empty XDG data/state/cache dirs, so a plugin or parser that
# is missing from the Nix store farm fails here instead of at first launch.
{
  pkgs,
  hmConfig,
}: let
  inherit (pkgs) lib;
  nvimFiles = lib.filterAttrs (name: _: lib.hasPrefix "nvim/" name) hmConfig.xdg.configFile;
  configHome = pkgs.linkFarm "nvim-config-home" (lib.mapAttrsToList (name: file: {
      inherit name;
      path = file.source;
    })
    nvimFiles);
in
  pkgs.runCommand "nvim-lazy-check" {
    # The unwrapped package, so the wrapper's LSP extraPackages closure is not pulled.
    nativeBuildInputs = [
      hmConfig.programs.neovim.package
      pkgs.git
      pkgs.gnugrep
    ];
  } ''
    export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config
    # Empty fish and hypr dirs make the dot extra want those parsers, as on real hosts.
    mkdir -p "$XDG_CONFIG_HOME/fish" "$XDG_CONFIG_HOME/hypr"
    ln -s ${configHome}/nvim "$XDG_CONFIG_HOME/nvim"
    export XDG_DATA_HOME=$TMPDIR/data XDG_STATE_HOME=$TMPDIR/state XDG_CACHE_HOME=$TMPDIR/cache
    mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    cd "$TMPDIR"
    nvim --headless "+checkhealth lazy" "+w! $TMPDIR/health.txt" +qa
    test -s "$TMPDIR/health.txt" || { echo 'checkhealth wrote no output' >&2; exit 1; }
    if grep -q ERROR "$TMPDIR/health.txt"; then cat "$TMPDIR/health.txt"; exit 1; fi
    printf 'local x = 1\n' > a.lua
    printf '{ x = 1; }\n' > a.nix
    # check.lua quits on its own; cquit runs only if it throws, which would hang otherwise.
    nvim --headless "+luafile ${./check.lua}" "+cquit 1"
    touch $out
  ''
