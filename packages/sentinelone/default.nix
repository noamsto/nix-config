# Version bump workflow (keeps repo lean — only one .deb at a time):
#
#   1. Download the new .deb from the SentinelOne console
#   2. Replace the file in this directory:
#        git rm packages/sentinelone/SentinelAgent_linux_x86_64_v<old>.deb
#        cp ~/Downloads/SentinelAgent_linux_x86_64_v<new>.deb packages/sentinelone/
#        git add packages/sentinelone/SentinelAgent_linux_x86_64_v<new>.deb
#   3. Update `version` and `src` below to match the new filename
#   4. Rebuild: `nh os switch`
#
# To reclaim space after several bumps, run once:
#   git filter-repo --path-glob 'packages/sentinelone/*.deb' --invert-paths
# (requires: nix shell nixpkgs#git-filter-repo — rewrites history, force-push needed)
{
  stdenv,
  lib,
  dpkg,
  autoPatchelfHook,
  zlib,
  elfutils,
  dmidecode,
  jq,
  gcc-unwrapped,
}:
stdenv.mkDerivation {
  pname = "sentinelone";
  version = "25.4.2.21";

  src = ./SentinelAgent_linux_x86_64_v25_4_2_21.deb;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  buildInputs = [
    zlib
    elfutils
    dmidecode
    jq
    gcc-unwrapped
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mv opt $out/opt

    ln -s $out/opt/sentinelone/bin/sentinelctl          $out/bin/sentinelctl
    ln -s $out/opt/sentinelone/bin/sentinelone-agent    $out/bin/sentinelone-agent
    ln -s $out/opt/sentinelone/bin/sentinelone-watchdog $out/bin/sentinelone-watchdog
    ln -s $out/opt/sentinelone/bin/addon-host           $out/bin/addon-host
    ln -s $out/opt/sentinelone/lib                      $out/lib

    runHook postInstall
  '';

  dontPatchELF = true;

  preFixup = ''
    patchelf --replace-needed libelf.so.0 libelf.so $out/opt/sentinelone/lib/libbpf.so
  '';

  meta = {
    description = "SentinelOne Linux Agent";
    homepage = "https://www.sentinelone.com";
    license = lib.licenses.unfree;
    platforms = ["x86_64-linux"];
    mainProgram = "sentinelctl";
  };
}
