{ stdenv, lib, autoPatchelfHook
}:

stdenv.mkDerivation rec {
  pname = "barracudavpn";
  version = "5.2.2";

  src = ./barracudavpn;
  
  system = "x86_64-linux";
 
  nativeBuildInputs = [
    autoPatchelfHook
  ];

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    install -m755 -D $src $out/bin/barracudavpn
  '';

  meta = with lib; {
    homepage = "https://barracuda.com";
    description = "Barracuda VPN";
    platforms = platforms.linux;
  };
}

