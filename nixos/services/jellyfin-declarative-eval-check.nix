# Eval check for services.jellyfinHost.declarative: asserts the rendered Jellarr
# config and jellarr-post JSON carry secret paths only, never credential values.
{
  pkgs,
  example,
}: let
  nixos = example.extendModules {
    modules = [
      {
        services.jellyfinHost = {
          enable = true;
          declarative = {
            enable = true;
            apiKeySecret = "/run/secrets/jellarr-api-key";
            openSubtitles = {
              usernameSecret = "/run/secrets/opensubtitles-username";
              passwordSecret = "/run/secrets/opensubtitles-password";
            };
            libraries = [
              {
                name = "Movies";
                collectionType = "movies";
                path = "/mnt/media/movies";
                subtitleDownloadLanguages = ["heb"];
                requirePerfectSubtitleMatch = false;
              }
            ];
          };
        };
      }
    ];
  };
  inherit (nixos.config.systemd) units;
  preStart = pkgs.writeText "jellarr-preStart" nixos.config.systemd.services.jellarr.preStart;
in
  pkgs.runCommand "jellyfin-declarative-eval-check" {
    nativeBuildInputs = [pkgs.jq pkgs.gnugrep];
  } ''
    postUnit=${units."jellarr-post.service".unit}/jellarr-post.service

    fail() {
      echo "FAIL: $1" >&2
      for f in "$@"; do
        [ -f "$f" ] && { echo "--- $f ---" >&2; cat "$f" >&2; }
      done
      exit 1
    }

    cfg=$(grep -o '/nix/store/[^ ]*-jellarr-config.yml' ${preStart} | head -n1)
    [ -n "$cfg" ] || fail "no jellarr config path in preStart" ${preStart}
    post=$(grep '^ExecStart=' $postUnit | grep -o '/nix/store/[^ ]*-jellarr-post.json')
    [ -n "$post" ] || fail "no post json path in ExecStart" $postUnit

    # jellarr config (JSON despite the .yml name)
    jq -e '.plugins == [{"name":"Open Subtitles"}]' $cfg >/dev/null \
      || fail "config plugins" $cfg
    jq -e '[.. | objects | keys[]] | any(. == "Username" or . == "Password") | not' $cfg >/dev/null \
      || fail "config has Username/Password key" $cfg
    jq -e 'all(.plugins[]; has("configuration") | not)' $cfg >/dev/null \
      || fail "config has plugin configuration" $cfg

    # jellarr-post JSON
    jq -e '.openSubtitles.usernameFile == "/run/secrets/opensubtitles-username"' $post >/dev/null \
      || fail "post usernameFile" $post
    jq -e '.openSubtitles.passwordFile == "/run/secrets/opensubtitles-password"' $post >/dev/null \
      || fail "post passwordFile" $post
    jq -e '.apiKeyFile == "/run/secrets/jellarr-api-key"' $post >/dev/null \
      || fail "post apiKeyFile" $post
    jq -e '.libraries == [{"name":"Movies","options":{"SubtitleDownloadLanguages":["heb"],"RequirePerfectSubtitleMatch":false}}]' $post >/dev/null \
      || fail "post libraries" $post
    jq -e '.plugins == ["Open Subtitles"]' $post >/dev/null \
      || fail "post plugins" $post
    jq -e '[.openSubtitles | .. | strings] | all(. == "/run/secrets/opensubtitles-username" or . == "/run/secrets/opensubtitles-password" or . == "4b9ed42f-5185-48b5-9803-6ff2989014c4" or . == "Open Subtitles")' $post >/dev/null \
      || fail "post openSubtitles holds an unexpected string" $post

    # post unit
    grep -q '^After=.*jellarr\.service' $postUnit || fail "post unit After" $postUnit
    grep -q '^User=root$' $postUnit || fail "post unit User" $postUnit

    for f in $cfg $post $postUnit; do
      if grep -q -e 'Password=' -e 'Username=' $f; then
        fail "credential assignment in $f" $f
      fi
    done

    touch $out
  ''
