{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libxcb,
  runtimeShell,
}: let
  version = "1.1.4";
  system = stdenv.hostPlatform.system;

  # Default (non-JIT) build. Do not edit version or hashes by hand: bump.sh
  # verifies the release signature against allowed_signers and rewrites them.
  platforms = {
    x86_64-linux = {
      target = "linux-x64";
      hash = "sha256-yrD3hRt/FR/e0jZb023DO3j9NRPU4S8I5wpK1VWrdZs=";
    };
    aarch64-linux = {
      target = "linux-arm64";
      hash = "sha256-Ke9XRyEEAAb/yooudJgvlgpAVCtccn/MYlOf+WWf0o0=";
    };
    aarch64-darwin = {
      target = "darwin-arm64";
      hash = "sha256-Celf5elnwEiIkhPOmAdyXLrjxHMd5+eRmXHfUkHSv4k=";
    };
  };
  platform = platforms.${system} or (throw "pi-bolt: unsupported system ${system}");
in
  stdenv.mkDerivation {
    pname = "pi-bolt";
    inherit version;

    src = fetchurl {
      url = "https://github.com/opensec-git/Pi-Bolt/releases/download/bolt-v${version}/pi-bolt-${platform.target}.tar.xz";
      inherit (platform) hash;
    };

    sourceRoot = "pi-bolt-${platform.target}";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [stdenv.cc.cc.lib libxcb];

    # The executable locates assets/, theme/ and package.json next to itself,
    # so the whole archive goes under libexec. Never strip: the Pi runtime is
    # embedded in the binary. On darwin skip fixup entirely to keep the code
    # signature intact.
    dontStrip = true;
    dontFixup = stdenv.hostPlatform.isDarwin;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/libexec $out/bin
      cp -r . $out/libexec/pi-bolt
      cat > $out/bin/pi-bolt <<SCRIPT
      #!${runtimeShell}
      # Nix owns the install: \`update\` and \`compile\` would rewrite the store, and
      # the remote-control service is deliberately not set up here.
      case "\''${1:-}" in
        update|compile)
          echo "pi-bolt ${version} is managed by Nix (nix-config packages/pi-bolt); bump it there (extensions: use pi update)." >&2
          exit 1
          ;;
        service)
          echo "pi-bolt service (remote control) is intentionally unavailable in this Nix package." >&2
          exit 1
          ;;
      esac
      # The pi wrapper sets PI_BOLT_ARGV0=pi so process matchers see \`pi\`; read it
      # once and clear it so child processes and a nested \`pi-bolt\` keep their own name.
      argv0=\''${PI_BOLT_ARGV0:-pi-bolt}
      unset PI_BOLT_ARGV0
      exec -a "\$argv0" $out/libexec/pi-bolt/pi "\$@"
      SCRIPT
      chmod +x $out/bin/pi-bolt
      runHook postInstall
    '';

    meta = {
      description = "Pi compiled ahead of time into one native executable";
      homepage = "https://github.com/opensec-git/Pi-Bolt";
      license = lib.licenses.mit;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "pi-bolt";
      platforms = builtins.attrNames platforms;
    };
  }
