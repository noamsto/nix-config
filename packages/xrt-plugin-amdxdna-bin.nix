# Pre-built xrt-plugin-amdxdna from Arch Linux.
# Upstream nix-amd-npu fails to compile this (query::aie_coredump::args missing).
# XRT dlopen's libxrt_driver_*.so.2 from its own lib/ directory at runtime.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zstd,
  xrt,
}:
stdenv.mkDerivation rec {
  pname = "xrt-plugin-amdxdna-bin";
  version = "2.21.75";

  src = fetchurl {
    url = "https://archlinux.org/packages/extra/x86_64/xrt-plugin-amdxdna/download/";
    hash = "sha256-k7HmhMgdckY0X/kw69VsNeW//hiM3K6AZrdnhrPLWy0=";
    name = "xrt-plugin-amdxdna-${version}.pkg.tar.zst";
  };

  nativeBuildInputs = [autoPatchelfHook zstd];

  buildInputs = [
    stdenv.cc.cc.lib # libstdc++
    xrt
  ];

  # autoPatchelf needs to find XRT libs in the nested path
  autoPatchelfSearchPaths = [
    "${xrt}/opt/xilinx/xrt/lib"
  ];

  unpackPhase = ''
    tar xf $src
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp usr/lib/libxrt_driver_xdna.so.${version} $out/lib/
    ln -s libxrt_driver_xdna.so.${version} $out/lib/libxrt_driver_xdna.so.2
  '';

  meta = with lib; {
    description = "AMD XDNA shim plugin for XRT NPU access (pre-built)";
    homepage = "https://github.com/amd/xdna-driver";
    license = licenses.asl20;
    platforms = ["x86_64-linux"];
  };
}
