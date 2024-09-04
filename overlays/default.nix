# ./overlays/default.nix
{inputs, ...}: {
  nixpkgs.overlays = [
    inputs.hyprpanel.overlay
    inputs.yazi.overlays.default

    (final: _: {
      stable = import inputs.nixpkgs-stable {
        system = final.system;
        config.allowUnfree = true;
      };
    })

    (final: prev: {
      # Use tmux fork until this issue is closed: https://github.com/tmux/tmux/issues/2705
      tmux = prev.tmux.overrideAttrs (prviousAttrs: {
        version = "next-3.4";
        patches = [];
        src = prev.fetchFromGitHub {
          owner = "tiagovla";
          repo = "tmux";
          rev = "b6be05261a4d92cf41156ccbf5f41d19ca18665f";
          sha256 = "sha256-w0Z2I+b95RYGrNvFqXbUwkcTTDUvi7RawuAgz5nGsl0=";
        };
      });
    })

    (final: prev: {
      zoom-us = prev.zoom-us.overrideAttrs (previousAttrs: let
        version = "6.0.12.5501";
        src = prev.fetchurl {
          url = "https://zoom.us/client/${version}/zoom_x86_64.pkg.tar.xz";
          hash = "sha256-h9gjVd7xqChaoC2BZWEhR5WdyfQrPiBjM2WHXMgp8uQ=";
        };
      in {
        inherit version;
        installPhase = ''
          runHook preInstall
          ${rec {
              aarch64-darwin = ''
                mkdir -p $out/Applications
                cp -R zoom.us.app $out/Applications/
              '';
              # darwin steps same on both architectures
              x86_64-darwin = aarch64-darwin;
              x86_64-linux = ''
                mkdir $out
                tar -C $out -xf ${src}
                mv $out/usr/* $out/
              '';
            }
            .${prev.system}
            or prev.throwSystem}
          runHook postInstall
        '';
      });
    })
  ];
}
