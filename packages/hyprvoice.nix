{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  pipewire,
  wtype,
  wl-clipboard,
  libnotify,
  whisper-cpp,
}:
buildGoModule rec {
  pname = "hyprvoice";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "LeonardoTrapani";
    repo = "hyprvoice";
    rev = "v${version}";
    hash = "sha256-geIjm5vChQwO44eSw8E9Tp8d4QkL3IGIdI7Xvpz9Eu8=";
  };

  vendorHash = "sha256-b1IsFlhj+xTQT/4PzL97YjVjjS7TQtcIsbeK3dLOxR4=";

  nativeBuildInputs = [makeWrapper];

  # Runtime dependencies
  buildInputs = [
    pipewire
    wtype
    wl-clipboard
    libnotify
  ];

  subPackages = ["cmd/hyprvoice"];

  postInstall = ''
    wrapProgram $out/bin/hyprvoice \
      --prefix PATH : ${lib.makeBinPath [
      wtype
      wl-clipboard
      libnotify
      whisper-cpp
    ]}
  '';

  meta = with lib; {
    description = "Voice-powered typing for Wayland/Hyprland desktops";
    homepage = "https://github.com/LeonardoTrapani/hyprvoice";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.linux;
    mainProgram = "hyprvoice";
  };
}
