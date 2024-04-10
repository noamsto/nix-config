{pkgs ? import <nixpkgs> {}}:
pkgs.buildGoModule {
  pname = "dbee";
  version = "0.1.3";
  src =
    pkgs.fetchFromGitHub {
      owner = "kndndrj";
      repo = "nvim-dbee";
      rev = "v0.1.3";
      hash = "sha256-M+2znUwQ5BhSlO3l91ALmFwrJbQS8Py/4Wltijl/FKI=";
    }
    + "/dbee";
  vendorHash = "sha256-0TIKX0OL5V3sk9V7e56YmNIzsUZku6Y8S22lVUGrsCY=";
  buildInputs = [pkgs.duckdb];
}
