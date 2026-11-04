# Shared MCP server definitions for AI tools (Claude Code, pi, etc.)
# Single source of truth - import this in each tool's module
{
  pkgs,
  lib,
  username,
}: let
  helpers = import ./mcp-helpers.nix {inherit pkgs;};

  homeRoot =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/Users"
    else "/home";
  homeDirectory = "${homeRoot}/${username}";

  # chromium is Linux-only in nixpkgs. On darwin, omit --executable-path so
  # playwright-mcp uses its own managed browser. The automation wrapper (and
  # any pkgs.chromium reference) must stay inside the Linux branch so darwin
  # eval never forces the chromium thunk (meta checks fail off-Linux).
  playwright =
    if pkgs.stdenv.hostPlatform.isLinux
    then let
      # Persistent profile + 1Password extension for easy logins. Spec:
      # docs/superpowers/specs/2026-08-03-playwright-1password-autofill-design.md
      playwrightMcpAutomation = pkgs.writeShellApplication {
        name = "playwright-mcp-automation";
        runtimeInputs = [pkgs.coreutils pkgs.jq];
        text = ''
          cache_home="''${XDG_CACHE_HOME:-$HOME/.cache}"
          user_data_dir="$cache_home/playwright-mcp-automation"
          nm_dir="$user_data_dir/NativeMessagingHosts"
          config_path="$user_data_dir/mcp-config.json"
          chromium_bin="${lib.getExe pkgs.chromium}"
          mcp_bin="${lib.getExe pkgs.playwright-mcp}"

          mkdir -p "$nm_dir"

          jq -n '{
            name: "com.1password.1password",
            description: "1Password BrowserSupport",
            path: "/run/wrappers/bin/1Password-BrowserSupport",
            type: "stdio",
            allowed_origins: [
              "chrome-extension://hjlinigoblmkhjejkmbegnoaljkphmgo/",
              "chrome-extension://bkpbhnjcbehoklfkljkkbbmipaphipgl/",
              "chrome-extension://gejiddohjgogedgjnonbofjigllpkmbf/",
              "chrome-extension://khgocmkkpikpnmmkgmdnfckapcdkgfaf/",
              "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/",
              "chrome-extension://dppgmdbiimibapkepcbdbmkaabgiofem/"
            ]
          }' >"$nm_dir/com.1password.1password.json"

          # 1Password comes from the ExtensionInstallForcelist policy
          # (nixos/desktop/1password). Two Playwright defaults block it:
          # --disable-extensions, and --disable-background-networking, which
          # stops the policy downloading the extension from the Web Store.
          # chromiumSandbox: Playwright otherwise adds --no-sandbox, which shows a
          # warning bar; the namespace sandbox works on NixOS.
          jq -n \
            --arg userDataDir "$user_data_dir" \
            --arg executablePath "$chromium_bin" \
            '{
              browser: {
                browserName: "chromium",
                userDataDir: $userDataDir,
                launchOptions: {
                  executablePath: $executablePath,
                  headless: false,
                  chromiumSandbox: true,
                  ignoreDefaultArgs: ["--disable-extensions", "--disable-background-networking"]
                }
              }
            }' >"$config_path"

          exec "$mcp_bin" --config "$config_path" "$@"
        '';
      };
    in {
      command = lib.getExe playwrightMcpAutomation;
      args = [];
      env = {
        PLAYWRIGHT_BROWSERS_PATH = "${homeDirectory}/.cache/ms-playwright";
      };
    }
    else {
      command = lib.getExe pkgs.playwright-mcp;
      args = [];
      env = {
        PLAYWRIGHT_BROWSERS_PATH = "${homeDirectory}/.cache/ms-playwright";
      };
    };
in {
  # Base MCPs - npx-style (avoids embedding deps that collide with cursor-agent)
  # Used by claude-code, amp, cursor (flat attribute)
  base = {
    context7 = {
      command = "${pkgs.context7-mcp}/bin/context7-mcp";
      args = [];
      env = {};
    };

    inherit playwright;

    firefox-devtools = helpers.mkNpxMcp {
      package = "firefox-devtools-mcp@latest";
      args = ["--connect-existing" "--marionette-port" "2828"];
    };
  };

  # Wrapper-based MCPs for configs that reference commands by name
  # These provide simple command names that work when the wrapper is in PATH
  wrappers = {
    playwright = pkgs.writeShellScriptBin "playwright-mcp-wrapper" ''
      exec ${playwright.command} ${lib.escapeShellArgs playwright.args} "$@"
    '';
  };

  # MCPs provided natively by claude.ai — exclude from Claude Code
  claudeAiProvided = ["linear"];

  # Re-export helpers for use in tool-specific configs
  inherit helpers;
}
