{pkgs ? import <nixpkgs> {}, ...}:
pkgs.stdenv.mkDerivation rec {
  pname = "libraspberrypi";
  version = "unstable-2024-03-13";

  src = pkgs.fetchFromGitHub {
    owner = "raspberrypi";
    repo = "utils";
    rev = "cf46fe84b2a345146e067a9a3529ba6e28517c8e";
    hash = "sha256-HVTWMG5Ko+RDZnZmKoGgPeZj9t2AAFLVchHiw6gDElg=";
  };

  nativeBuildInputs = with pkgs; [cmake pkg-config dtc];
  cmakeFlags = [
    # -DARM64=ON disables all targets that only build on 32-bit ARM; this allows
    # the package to build on aarch64 and other architectures
    "-DARM64=${
      if pkgs.stdenv.hostPlatform.isAarch32
      then "OFF"
      else "ON"
    }"
    "-DVMCS_INSTALL_PREFIX=${placeholder "out"}"
  ];

  meta = with pkgs.lib; {
    description = "Userland tools & libraries for interfacing with Raspberry Pi hardware";
    homepage = "https://github.com/raspberrypi/utils";
    license = licenses.bsd3;
    platforms = ["armv6l-linux" "armv7l-linux" "aarch64-linux" "x86_64-linux"];
    maintainers = with maintainers; [dezgeg tkerber];
  };
}
