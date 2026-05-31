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
`determinateNix.customSettings` in `default.nix`.

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
- **Expect build-time failures here that the Linux eval could not catch.** Linux
  eval only surfaces missing-attribute errors (custom flakes lacking
  `aarch64-darwin` outputs); Linux-only *nixpkgs* packages (`meta.platforms =
  linux`) evaluate fine and only fail when actually built on the Mac. This is the
  deferred "drive to green" loop — for each failure:
  - **Linux-only nixpkgs package** in a shared `home/` module → wrap it with
    `lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ... ]` (add `pkgs`/`lib` to
    the module args if absent).
  - **Custom flake input with no darwin output** (`wtc`, `zr`, `lazytmux`, `pi`
    are already gated; if a new one appears) → gate it the same way, or add
    `aarch64-darwin` to that flake upstream.
  - **Config block tied to a gated import** → wrap in
    `lib.mkIf pkgs.stdenv.hostPlatform.isLinux { ... }` (config-level mkIf only —
    never condition `imports` on `pkgs`, it causes infinite recursion).
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

## 7. FlakeHub Cache auth (replaces the Linux agenix symlink)

The Linux hosts read FlakeHub auth from an agenix secret at
`/run/agenix/noams_flakehub`; that path doesn't exist on darwin and the symlink
is gated off. Authenticate via Determinate instead:

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
