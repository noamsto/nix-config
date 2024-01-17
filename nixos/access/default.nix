{pkgs ? import <nixpkgs> {}, ...}: let
  repo = "https://downloads.fyde.com/apt/pool/stable/a/ac";
  # repo = "https://downloads.fyde.com/apt/pool/stable/a/ac/access_0.30.3_amd64.deb";
in
  pkgs.stdenv.mkDerivation rec {
    pname = "access";
    version = "0.30.3";

    src = pkgs.fetchurl {
      url = "${repo}/${pname}_${version}_amd64.deb";
      sha256 = "2yGFhYSoh5ltedrkHKBm+L9Ik9jf/TsWR07oK6N8svI=";
    };
    # unpackPhase = "dpkg-deb -x $src .";

    nativeBuildInputs = with pkgs; [
      dpkg
      autoPatchelfHook
      wrapGAppsHook
      qt6.wrapQtAppsHook
      qt6.qtbase
    ];
    buildInputs = with pkgs; [
      alsa-lib
      at-spi2-atk
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      libuuid.lib
      nspr
      nss
      pango
      xorg.libX11
      xorg.libXScrnSaver
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXtst
      xorg.libxcb
    ];
    dontWrapQtApps = true;

    installPhase = ''
      mkdir -p $out/bin
      cp -r /usr/ $out
      cp -r /opt $out/opt
      ln -s $out/opt/cgaccess $out/bin

    '';
  }
