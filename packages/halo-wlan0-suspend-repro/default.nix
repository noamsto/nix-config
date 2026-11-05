{
  writeShellApplication,
  util-linux,
  systemd,
  iproute2,
  kmod,
  gnugrep,
  iwd,
}:
writeShellApplication {
  name = "halo-wlan0-suspend-repro";
  runtimeInputs = [util-linux systemd iproute2 kmod gnugrep iwd];
  text = builtins.readFile ./halo-wlan0-suspend-repro.sh;

  meta = {
    description = "Suspend/resume repro harness for halo's wlan0 wedge (#219) -- measurement only, no fix";
    mainProgram = "halo-wlan0-suspend-repro";
  };
}
