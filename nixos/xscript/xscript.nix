{pkgs ? import <nixpkgs> {}, ...}:
pkgs.stdenv.mkDerivation (finalAttrs: rec {
  pname = "xscript";
  version = "unstable-08-18-2023";

  src = pkgs.fetchFromGitHub {
    owner = "geekworm-com";
    repo = "xscript";
    rev = "8dddc2d2764ceab7c0960468c947a5c700a22331";
    hash = "sha256-iJLlOeRlB7AJwlhYmtsZpIVdj6vAdxzlxA+aOhgF9t0=";
  };

  nativeBuildInputs = with pkgs; [
    makeWrapper
  ];
  buildInputs = with pkgs; [
    gawk
  ];

  installPhase = ''

    mkdir -p $out/bin
    mkdir -p $out/lib/systemd/system

    cp $src/x-c1-{fan,pwr}.service $out/lib/systemd/system

    install -Dm755 $src/x-c1-{fan,pwr,softsd}.sh $out/bin/

    substituteInPlace $out/lib/systemd/system/x-c1-fan.service \
                      --replace-warn /usr/local/bin $out/bin

    substituteInPlace $out/lib/systemd/system/x-c1-pwr.service \
                      --replace-warn /usr/local/bin $out/bin

    substituteInPlace $out/bin/x-c1-pwr.sh \
                     --replace-warn /bin/sleep sleep

    substituteInPlace $out/bin/x-c1-softsd.sh \
                     --replace-warn /bin/sleep sleep

    wrapProgram $out/bin/x-c1-fan.sh --prefix PATH : "${pkgs.lib.makeBinPath buildInputs}"

  '';

  meta = {
    description = "Power and Fan control for Naspi Gemini";
    homepage = "https://github.com/geekworm-com/xscript";
    license = pkgs.lib.licenses.mit;

    # maintainers = with lib.maintainers; [];
  };
})
