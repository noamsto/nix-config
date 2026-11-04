{
  pkgs,
  lib,
  ...
}:
# AMD VAAPI render profiles for Kdenlive. Kdenlive defaults to software
# (libx264/libx265) encoders; these offload the final encode to the iGPU's
# fixed-function encoder. Kdenlive loads every *.xml under its export dir with
# the same parser as the stock profiles.xml, so this drops in as an extra
# "AMD VAAPI (GPU)" render group.
#
# `vf=format=nv12,hwupload` is mandatory: h264_vaapi/hevc_vaapi only accept
# frames already uploaded to GPU surfaces. Verified working on the P14s Gen 5
# (HawkPoint iGPU, radeonsi) via a melt h264_vaapi encode.
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  xdg.dataFile."kdenlive/export/vaapi.xml".text = ''
    <?xml version="1.0"?>
    <profiles version="0.1">
     <group renderer="avformat" type="av" id="amd-vaapi">
      <name>AMD VAAPI (GPU)</name>
      <profile name="VAAPI H.264 (GPU)" extension="mp4"
       bitrates="30000,1000" defaultbitrate="8000"
       audiobitrates="256,64" defaultaudiobitrate="160"
       args="f=mp4 movflags=+faststart vcodec=h264_vaapi vaapi_device=/dev/dri/renderD128 vf=format=nv12,hwupload vb=%bitrate+'k' acodec=aac ab=%audiobitrate+'k'"/>
      <profile name="VAAPI H.265/HEVC (GPU)" extension="mp4"
       bitrates="30000,1000" defaultbitrate="6000"
       audiobitrates="256,64" defaultaudiobitrate="160"
       args="f=mp4 movflags=+faststart vcodec=hevc_vaapi vaapi_device=/dev/dri/renderD128 vf=format=nv12,hwupload vb=%bitrate+'k' acodec=aac ab=%audiobitrate+'k'"/>
     </group>
    </profiles>
  '';
}
