# mbp-m4-pro bootstrap

This host (`darwinConfigurations.mbp-m4-pro`) is **built and verified on the Mac**
— the config repo's primary dev host is `x86_64-linux` and cannot build
`aarch64-darwin`. The scaffolding (flake wiring, host module, options, known
Linux-only gating) was authored and eval-checked on Linux; the first
`darwin-rebuild switch` here is the authoritative test.

Stack: Determinate Nix (owns Nix) + nix-darwin (macOS system) + nix-homebrew
(declarative casks) + system-integrated Home Manager (reuses the shared `home/`
modules).

## 1. Install Determinate Nix

Use the Determinate installer for macOS: <https://docs.determinate.systems/>
This config sets `determinateNix.enable = true`, so Determinate manages Nix and
nix-darwin's `nix.*` options are intentionally inert. Caches are declared via
`determinateNix.customSettings` in `darwin/base.nix` (`darwinModules.base`).

## 2. Install Rosetta 2 (for `enableRosetta` casks)

```sh
softwareupdate --install-rosetta --agree-to-license
```

## 3. Clone the config

```sh
git clone <repo-url> ~/nix-config
cd ~/nix-config
```

## 4. First switch (nix-darwin not yet on PATH)

```sh
nix run nix-darwin -- switch --flake ~/nix-config#mbp-m4-pro
```

- Requires sudo for system activation.
- nix-homebrew installs Homebrew into `/opt/homebrew` on first run (owned by
  `noams`).
- Homebrew 6.0 tap-trust for the non-official `mediosz/tap` (swipeaerospace) is
  handled declaratively — `homebrew.onActivation.extraEnv.XDG_CONFIG_HOME` points
  brew at a store-baked `trust.json`. No manual `brew trust` needed.
- The `mediosz/tap` cask is patched in-flake: its `postflight_steps` block
  interpolates a bare `appdir`, which Homebrew 7 no longer provides, making the
  cask unreadable and aborting `brew bundle`. The block is stripped and its
  quarantine strip moved into the SwipeAeroSpace LaunchAgent supervisor (the
  build is ad-hoc signed, so a quarantined bundle won't launch at all). Revert
  both once upstream regenerates the cask.
- **The full config already evaluates cleanly on Linux** — the entire darwin
  system toplevel (`config.system.build.toplevel.drvPath`) instantiates without
  error, so all Linux-only-package gating and missing-attr issues are resolved.
  Remaining Mac-side failures, if any, would be genuine *build/realisation*
  problems (a compiler/SDK missing, a cask issue, an import-from-derivation that
  needs a real darwin builder) — not the "drive to green" gating loop, which is
  effectively done.
- If a new gating gap does appear, the patterns are:
  - **Linux-only nixpkgs package** in a shared `home/` module → wrap it with
    `lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ... ]` (add `pkgs`/`lib` to
    the module args if absent).
  - **Linux-only HM sub-module** (e.g. `xdg.mimeApps`) → `lib.mkIf
    pkgs.stdenv.hostPlatform.isLinux { ... }` so it stays un-enabled off-Linux.
  - **Config block tied to a gated import** → `lib.mkIf
    pkgs.stdenv.hostPlatform.isLinux { ... }` (config-level mkIf only — never
    condition `imports` on `pkgs`, it causes infinite recursion).
  Re-run the switch after each fix.

## 5. Confirm Claude Desktop

```sh
ls /Applications/Claude.app
```

## 6. Subsequent rebuilds

```sh
darwin-rebuild switch --flake ~/nix-config#mbp-m4-pro
# or
nh darwin switch ~/nix-config
```

## 7. FlakeHub Cache auth

Authenticate to FlakeHub Cache via Determinate:

```sh
sudo determinate-nixd login
```

## 8. Set fish as login shell

nix-darwin doesn't change the shell of a pre-existing macOS account. After the
first switch (which puts fish on the system):

```sh
echo (which fish) | sudo tee -a /etc/shells
chsh -s (which fish)
```

## 9. Promote Homebrew cleanup

`homebrew.onActivation.cleanup` starts at `"uninstall"` (removes undeclared casks
but keeps their data). Once the cask list in `default.nix` is complete, change it
to `"zap"` for fully declarative cask management.

## Known deferrals (first cut)

- `foot` (Wayland terminal), `wtc`, `zr`, `lazytmux`/worktrunk, and `pi` are gated
  to Linux. Add `aarch64-darwin` outputs to the personal flakes (`wtc`, `zr`,
  `lazytmux`) later to re-enable on the Mac.
- agenix system secrets are not configured on darwin.
- Linux-specific binary caches (hyprland, noctalia, nix-amd-ai, vicinae, yazi)
  are intentionally omitted from `determinateNix.customSettings`.
- `system.stateVersion = 6` — verify against the nix-darwin changelog if a newer
  release expects a different value.
```
