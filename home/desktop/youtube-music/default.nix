{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}: let
  # Pin to a commit SHA, never a branch (repo gotcha). Both flavor files default
  # --ctp-accent to mauve, so no accent patch is needed.
  ytmSrc = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "youtubemusic";
    rev = "dc35fc46232e389ff761adec8242f956af405880";
    hash = "sha256-K5iwNBA/6/JDmmt/u9Dnsk0lvWY12YpY+BIScrRaDGw=";
  };

  # One file that auto-switches via prefers-color-scheme: Mocha when the system
  # (portal/OS) reports dark, Latte when light. Wrapping each whole flavor file
  # in @media is valid here — neither file has @charset/@import.
  ytmCatppuccinTheme = pkgs.runCommand "catppuccin-auto.css" {} ''
    logoB64="$(base64 -w0 ${./logo-latte.svg})"
    {
      echo '@media (prefers-color-scheme: dark) {'
      cat ${ytmSrc}/src/mocha.css
      echo '}'
      echo '@media (prefers-color-scheme: light) {'
      cat ${ytmSrc}/src/latte.css
      # Upstream leaves the nav logo as YT's dark-mode asset (white "Music"
      # wordmark), invisible on Latte's light background. Swap in a Latte variant
      # whose wordmark is recolored to --ctp-text; the red play button is intact.
      echo 'ytmusic-logo img.logo { content: url("data:image/svg+xml;base64,'"$logoB64"'") !important; }'
      echo '}'
    } > "$out"
  '';

  # YTM (Electron) stores user data under ~/Library/Application Support on macOS
  # and ~/.config on Linux. config.json holds options.themes = [ <css paths> ].
  configFile =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "${config.home.homeDirectory}/Library/Application Support/YouTube Music/config.json"
    else "${config.home.homeDirectory}/.config/YouTube Music/config.json";

  # pear-desktop is installed on Linux desktops (desktop-packages) and on macOS
  # (home/darwin). Match that exactly so a headless Linux host gets nothing.
  ytmInstalled = osConfig.desktop.mode != "none" || pkgs.stdenv.hostPlatform.isDarwin;
in {
  # Idempotently register the theme path in YTM's config.json, preserving every
  # app-mutated key (window position, plugins, …). restartOnConfigChanges is
  # false upstream, so this never triggers a spurious restart.
  home.activation.youtubeMusicCatppuccin = lib.mkIf ytmInstalled (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      cfg=${lib.escapeShellArg configFile}
      themePath=${lib.escapeShellArg "${ytmCatppuccinTheme}"}
      $DRY_RUN_CMD mkdir -p "$(dirname "$cfg")"
      if [ -f "$cfg" ]; then
        tmp="$($DRY_RUN_CMD mktemp)"
        $DRY_RUN_CMD ${pkgs.jq}/bin/jq --arg p "$themePath" '.options.themes = [$p]' "$cfg" > "$tmp" \
          && $DRY_RUN_CMD mv "$tmp" "$cfg"
      else
        $DRY_RUN_CMD ${pkgs.jq}/bin/jq -n --arg p "$themePath" '{options: {themes: [$p]}}' > "$cfg"
      fi
    ''
  );
}
