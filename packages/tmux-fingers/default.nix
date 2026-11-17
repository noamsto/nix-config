# Pins an unreleased fork commit (noamsto/tmux-fingers PR #2, OSC 8 hyperlink
# hints). Drop once upstream releases it and nixpkgs picks it up.
{
  mkTmuxPlugin,
  replaceVars,
  fetchFromGitHub,
  crystal,
}: let
  fingers = crystal.buildCrystalPackage rec {
    format = "shards";
    version = "2.7.1";
    pname = "fingers";
    src = fetchFromGitHub {
      owner = "noamsto";
      repo = "tmux-fingers";
      rev = "e72c55dfa501da0c8035875f766789ddee5d543b";
      hash = "sha256-k8TjN8Y5V26uFKh3eY4JHTZMQ/xU2XVkKDpxUkHKJio=";
    };

    shardsFile = ./shards.nix;
    crystalBinaries.tmux-fingers.src = "src/fingers.cr";

    postInstall = ''
      shopt -s dotglob extglob
      rm -rv !("tmux-fingers.tmux"|"bin")
      shopt -u dotglob extglob
    '';

    # TODO: Needs starting a TMUX session to run tests
    # Unhandled exception: Missing ENV key: "TMUX" (KeyError)
    doCheck = false;
    doInstallCheck = false;

    meta = {
      homepage = "https://github.com/Morantron/tmux-fingers";
    };
  };
in
  mkTmuxPlugin {
    inherit (fingers) version src meta;

    pluginName = fingers.src.repo;
    rtpFilePath = "tmux-fingers.tmux";

    patches = [
      (replaceVars ./fix.patch {
        tmuxFingersDir = "${fingers}/bin";
      })
    ];
  }
