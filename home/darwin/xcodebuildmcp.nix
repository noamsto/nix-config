# XcodeBuildMCP CLI — xcodebuild/simctl plus AXe-backed simulator UI automation.
# Driven by the agent skill in home/ai/claude-code/skills/xcodebuildmcp-cli.
{
  lib,
  pkgs,
  ...
}: let
  # Not in nixpkgs, hence npx. Pinned so a rebuild is the only thing that can
  # change the toolchain under a running agent.
  version = "2.7.0";

  xcodebuildmcp = pkgs.writeShellApplication {
    name = "xcodebuildmcp";
    runtimeInputs = [pkgs.nodejs];
    text = ''
      # Nix points DEVELOPER_DIR at the apple-sdk store path, which ships no
      # SimulatorKit.framework, so AXe cannot load simulator support. The daemon
      # inherits this and caches it until `daemon restart`.
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

      # No cd: the daemon keys its workspace off the caller's cwd, which is what
      # gives each worktree its own daemon and its own simulator.
      exec npx -y xcodebuildmcp@${version} "$@"
    '';
  };
in {
  home.packages = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin [xcodebuildmcp];
}
