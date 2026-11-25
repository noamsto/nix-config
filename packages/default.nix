{lib, ...}: {
  perSystem = {pkgs, ...}: let
    piExtensions = pkgs.callPackage ./pi-extensions {};
    pi-bolt = pkgs.callPackage ./pi-bolt {};
    silero-vad = pkgs.callPackage ./silero-vad.nix {};
    voxtype-gemini = pkgs.callPackage ./voxtype-gemini {inherit silero-vad;};
  in {
    # linear-cli ships prebuilt binaries for both linux and darwin, and the pi
    # extensions are portable npm packages, so both live outside the Linux-only
    # guard below and build on every system.
    #
    # The rest are Linux-only (claude-squad, …). Guarding them keeps
    # `packages.aarch64-darwin` from trying to build them on macOS.
    packages =
      {
        deja-vu = pkgs.callPackage ./deja-vu.nix {};
        gh-repo-defaults = pkgs.callPackage ./gh-repo-defaults {};
        heebo-sans-hebrew = pkgs.callPackage ./heebo-sans-hebrew.nix {};
        linear-cli = pkgs.callPackage ./linear-cli.nix {};
        lock-commit = pkgs.callPackage ./lock-commit.nix {};
        inherit pi-bolt;
        inherit (piExtensions) pi-lens pi-vim pi-web-access rpiv-todo;
        pi-bolt-compiled = pkgs.callPackage ./pi-bolt/compiled.nix {
          inherit pi-bolt;
          extensions = [
            "${piExtensions.pi-lens}/lib/node_modules/pi-lens"
            "${piExtensions.pi-vim}/lib/node_modules/pi-vim"
            "${piExtensions.pi-web-access}/lib/node_modules/pi-web-access"
            "${piExtensions.rpiv-todo}/lib/node_modules/@juicesharp/rpiv-todo"
          ];
        };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        ytm-rs-macos = pkgs.callPackage ./ytm-rs-macos.nix {};
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        claude-squad = pkgs.callPackage ./claude-squad {};
        halo-wlan0-suspend-repro = pkgs.callPackage ./halo-wlan0-suspend-repro {};
        kitty-bidi = pkgs.callPackage ./kitty-bidi {};
        kitty-bidi-unwrapped = (pkgs.callPackage ./kitty-bidi {}).unwrapped;
        sherpa-dictate = pkgs.callPackage ./sherpa-dictate {inherit silero-vad voxtype-gemini;};
        inherit voxtype-gemini;
        inherit (pkgs) ytm-rs;
      }
      # AirConnect ships only static x86_64-linux binaries (meta.platforms), so
      # evaluating it on aarch64-linux fails.
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        airconnect = pkgs.callPackage ./airconnect.nix {};
      };
  };
}
