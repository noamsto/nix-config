{
  stdenvNoCC,
  fetchurl,
  unzip,
}: let
  version = "2.0.2";
  system = stdenvNoCC.hostPlatform.system;

  arch =
    {
      aarch64-darwin = "aarch64";
      x86_64-darwin = "x86_64";
    }
    .${
      system
    }
    or (throw "ytm-rs-macos: unsupported system ${system}");

  hashes = {
    aarch64 = "sha256-Y7Y3moqT1O9w5P9Qb0w8rLIHSyVRQgWsUbOudSMkeWI=";
    x86_64 = "sha256-/CS/P97YmU+fLhsF5qwgIEKhf36jAtBM/HbGE6af1sw=";
  };
in
  stdenvNoCC.mkDerivation {
    pname = "ytm-rs";
    inherit version;

    src = fetchurl {
      url = "https://github.com/grapedjuice/ytm-rs/releases/download/v${version}/ytm-rs-portable-${version}-macos-${arch}.zip";
      hash = hashes.${arch};
    };

    nativeBuildInputs = [unzip];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications
      cp -r ytm-rs.app $out/Applications/
      # portable.txt switches the app to portable mode, which writes data/
      # beside the .app; that is impossible in the read-only store. Removing
      # it invalidates the bundle's ad-hoc code signature (it is listed in
      # CodeResources) and leaves the app's self-updater on: turn Settings >
      # Automatic updates off once on the Mac and bump `version` here instead.
      rm -f $out/Applications/ytm-rs.app/Contents/Resources/portable.txt
      runHook postInstall
    '';

    dontFixup = true;

    meta = {
      description = "Native YouTube Music client (macOS release build)";
      homepage = "https://github.com/grapedjuice/ytm-rs";
      platforms = ["aarch64-darwin" "x86_64-darwin"];
    };
  }
