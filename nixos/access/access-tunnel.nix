{pkgs ? import <nixpkgs> {}, ...}: let
  repo = "https://downloads.fyde.com/apt/pool/stable/a/ac";
in
  pkgs.stdenv.mkDerivation rec {
    pname = "access-tunnel";
    version = "2.5.3";

    src = pkgs.fetchurl {
      url = "${repo}/${pname}_${version}_amd64.deb";
      sha256 = "sha256-tejXcLUhy5Yc1Gm2gPyhInrw47Ch/HA/tX+uISTW9Bo=";
    };

    nativeBuildInputs = with pkgs; [
      dpkg
      autoPatchelfHook
    ];

    unpackPhase = "dpkg-deb -x $src .";

    installPhase = ''
      mkdir -p $out/bin
      mkdir -p $out/lib/systemd/system

      cp -r ./opt $out/opt
      ln -s $out/opt/access/access-interface $out/bin
      ln -s $out/opt/access/access-tunnel $out/bin

      substitute $out/opt/access/services/access-interface.service \
                $out/lib/systemd/system/access-interface.service \
                --replace-quiet /opt/access/access-interface $out/bin/access-interface

      substitute $out/opt/access/services/access-tunnel.service \
                $out/lib/systemd/system/access-tunnel.service \
                --replace-quiet /opt/access/access-tunnel $out/bin/access-tunnel

    '';
  }
