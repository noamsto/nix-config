{
  lib,
  kitty,
  fetchFromGitHub,
  buildGo126Module,
  makeBinaryWrapper,
  makeDesktopItem,
  runCommand,
  nerd-fonts,
  fribidi,
  brotli,
  libxrender,
  vulkan-headers,
  vulkan-loader,
  libGL,
  libx11,
  wayland,
}: let
  version = "0.50.0-bidi";

  src = fetchFromGitHub {
    owner = "noamsto";
    repo = "kitty";
    rev = "5bc2f21d8ab6ad61412f3a2f7d93339582e1c859";
    hash = "sha256-fsqz4k6S6iC3XQl7iVGovsATay+DISKlfvRxAACdMKA=";
  };

  unwrapped = kitty.overrideAttrs (old: {
    pname = "kitty-bidi-unwrapped";
    inherit version src;

    inherit
      ((buildGo126Module {
        pname = "kitty-bidi-go-modules";
        inherit src version;
        vendorHash = "sha256-6E7C5DrbFSerYPY1bi8S4/itW4k67Qie262yl010OBg=";
      }))
      goModules
      ;

    buildInputs =
      old.buildInputs
      ++ [
        fribidi
        brotli
        libxrender
        vulkan-headers
      ];

    # The fork's gpu/ drivers dlopen bare sonames, which do not resolve on NixOS.
    postPatch =
      old.postPatch
      + ''
        substituteInPlace gpu/vulkan/driver.c \
          --replace-fail 'libvulkan.so.1' '${lib.getLib vulkan-loader}/lib/libvulkan.so.1'
        substituteInPlace gpu/opengl/egl.c \
          --replace-fail 'libwayland-egl.so.1' '${lib.getLib wayland}/lib/libwayland-egl.so.1' \
          --replace-fail 'libGL.so.1' '${lib.getLib libGL}/lib/libGL.so.1'
        substituteInPlace gpu/opengl/glx.c \
          --replace-fail 'libGL.so.1' '${lib.getLib libGL}/lib/libGL.so.1' \
          --replace-fail 'libX11.so.6' '${lib.getLib libx11}/lib/libX11.so.6' \
          --replace-fail 'libXrender.so.1' '${lib.getLib libxrender}/lib/libXrender.so.1'
        substituteInPlace gpu/vulkan/surfaces.c \
          --replace-fail 'libX11.so.6' '${lib.getLib libx11}/lib/libX11.so.6'
        substituteInPlace glfw/x11_init.c \
          --replace-fail 'libXrender.so.1' '${lib.getLib libxrender}/lib/libXrender.so.1'
      '';

    preCheck =
      old.preCheck
      + ''
        # Give the sandbox a font; fontconfig's default fonts.conf reads $XDG_DATA_HOME/fonts.
        export XDG_DATA_HOME=$TMPDIR/xdg
        mkdir -p $XDG_DATA_HOME/fonts
        ln -s ${nerd-fonts.symbols-only}/share/fonts/truetype $XDG_DATA_HOME/fonts/
      '';
  });

  desktopItem = makeDesktopItem {
    name = "kitty-bidi";
    desktopName = "Kitty (bidi)";
    exec = "kitty-bidi";
    icon = "kitty";
    terminal = false;
    categories = ["System" "TerminalEmulator"];
  };
in
  runCommand "kitty-bidi-${version}" {
    nativeBuildInputs = [makeBinaryWrapper];
    passthru = {inherit unwrapped;};
    meta = {
      inherit (unwrapped.meta) homepage license platforms;
      description = "Kitty with bidirectional text support, installed as kitty-bidi";
      mainProgram = "kitty-bidi";
    };
  } ''
    makeWrapper ${unwrapped}/bin/kitty $out/bin/kitty-bidi \
      --add-flags "-o env=KITTY_BIDI=1"
    install -Dm444 ${desktopItem}/share/applications/kitty-bidi.desktop \
      $out/share/applications/kitty-bidi.desktop
  ''
