{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  libsecret,
}: let
  version = "2.6.0";
  system = stdenv.hostPlatform.system;

  target =
    {
      x86_64-linux = "x86_64-unknown-linux-gnu";
      aarch64-linux = "aarch64-unknown-linux-gnu";
      x86_64-darwin = "x86_64-apple-darwin";
      aarch64-darwin = "aarch64-apple-darwin";
    }
    .${
      system
    }
    or (throw "linear-cli: unsupported system ${system}");

  hashes = {
    x86_64-unknown-linux-gnu = "sha256-u8udNlMIvDcooeyZE60YgPiMDOaHZzgyl+NIwFfzW40=";
    aarch64-unknown-linux-gnu = "sha256-VcxKaySJpAOtnrgPYS36hBKHv6FrmDkLtNTgcteeI2E=";
    x86_64-apple-darwin = "sha256-CKuhmvTwBinl6JqwQBfTHRhXP7ydySIoCChwL9riej8=";
    aarch64-apple-darwin = "sha256-uavdS1rsFEWeQ0oomSA3V96K6EfwVerk8frue7H7wHg=";
  };
in
  stdenv.mkDerivation {
    pname = "linear-cli";
    inherit version;

    src = fetchurl {
      url = "https://github.com/schpet/linear-cli/releases/download/v${version}/linear-${target}.tar.xz";
      hash = hashes.${target};
    };

    sourceRoot = "linear-${target}";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [makeWrapper];

    # `deno compile` appends the JS bundle to the end of the ELF; patchelf
    # relocates it and the binary then dies with "Could not find standalone
    # binary section". So we deliberately leave the ELF untouched (no
    # autoPatchelfHook, no strip) and lean on the host's nix-ld to satisfy the
    # FHS interpreter. The wrapper feeds nix-ld libgcc_s (the one runtime lib
    # outside glibc) so this doesn't hinge on the host's nix-ld library list.
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 linear $out/bin/linear
      runHook postInstall
    '';

    # The CLI shells out to `secret-tool` (libsecret) to reach the Secret
    # Service; it never links libsecret itself. Hook and `-B` monitor callers
    # do not inherit the interactive profile PATH, so the binary has to carry
    # secret-tool on its own PATH.
    postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
      wrapProgram $out/bin/linear \
        --prefix NIX_LD_LIBRARY_PATH : ${lib.makeLibraryPath [stdenv.cc.cc.lib]} \
        --prefix PATH : ${lib.makeBinPath [libsecret]}
    '';

    meta = {
      description = "Linear from the command line: list, start, and create PRs for Linear issues";
      homepage = "https://github.com/schpet/linear-cli";
      license = lib.licenses.isc;
      mainProgram = "linear";
      platforms = lib.platforms.unix;
    };
  }
