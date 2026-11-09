# nix-config

A reusable NixOS, nix-darwin and Home Manager library built with
[flake-parts](https://flake.parts), plus one buildable example host
(`hosts/example`). The author's real machines live in a separate private flake
that imports this one as an input.

Supported systems: `x86_64-linux`, `aarch64-linux` (Raspberry Pi) and
`aarch64-darwin` (the darwin modules).
`desktop.mode` is `none` or `hyprland`.

## Exported outputs

| Output | Attributes |
| --- | --- |
| `nixosModules` | `default`, `options`, `core`, `desktop`, `hyprland`, `laptop`, `hardware`, `services`, `steam-console`, `virtualization`, `xremap`, `overlays`, `lanzaboote`, `udev-hwmon`, `iwd-known-networks`, `nice-looking-console`, `rpi`, `home` |
| `homeModules` | `default`, `ai`, `git`, `nvim`, `ssh` |
| `darwinModules` | `default`, `options`, `priors`, `overlays`, `base`, `home` |
| `overlays` | `default` |
| `lib` | `caches`, `homeAliases`, `files` |
| `packages` | `deja-vu`, `gh-repo-defaults`, `linear-cli`, `pi-bolt`, `pi-bolt-compiled`, `pi-lens`, `pi-vim`, `pi-web-access`, `rpiv-todo` on all systems; `claude-squad`, `halo-wlan0-suspend-repro`, `sherpa-dictate` on Linux only; `airconnect` on `x86_64-linux` only |
| `nixosConfigurations` | `example`, `example-desktop` (Hyprland laptop, eval only), `example-rpi4` (aarch64-linux Raspberry Pi 4) |
| `checks`, `formatter`, `devShells` | per system, defined in `flake-modules/development.nix` |

Modules are assembled in `flake-modules/exports.nix`; packages in
`packages/default.nix`.

## Consuming it

```nix
{
  inputs.nix-config.url = "github:noamsto/nix-config";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, nix-config, ...}: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        nix-config.nixosModules.options
        nix-config.nixosModules.default
        nix-config.nixosModules.home
        ./hardware-configuration.nix # hostPlatform, fileSystems, boot loader
        {
          username = "me";
          hostname = "myhost";
          email = "me@example.com";
          machine.type = "laptop";
          desktop.mode = "none";
          priors.personalStore = {
            id = "my-personal-store";
            remote = "ssh://git@example.invalid/me/personal-store.git";
          };
        }
      ];
    };
  };
}
```

Import `nixosModules.options` (or `darwinModules.options` on macOS) so the
custom options exist; the other modules and the Home Manager modules read them
through `osConfig`. The snippet is a sketch; `hosts/example/default.nix` is the
complete, evaluable reference.

`options.nix` declares:

- Core options: `username`, `email`, `hostname`, `flakePath`, `desktop.mode`
  (`none` or `hyprland`) and `machine.type` (`server`, `desktop` or `laptop`).
- The `nix-config.*` namespace for host-specific behaviour, so shared modules
  never branch on the hostname. This includes
  `nix-config.wallpapers.default` (image for hyprpaper; falls back to a nixos-artwork wallpaper) and
  `nix-config.wallpapers.directory` (images linked as `~/Pictures/Wallpapers`;
  `null` links nothing).

## Raspberry Pi

`nixosModules.rpi` is a generic headless Raspberry Pi base: board support from
[nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi), a wheel user
with SSH keys, key-only sshd, DHCP networking and this library's caches. Set
`nix-config.rpi.board` (`rpi4`) and `nix-config.rpi.sshAuthorizedKeys`, plus
`username` and `hostname`; none has a default. Without
`nix-config.user.hashedPasswordFile` the user has no password and wheel gets
passwordless sudo; setting the file turns the sudo password back on.

Build the host with `nixos-raspberrypi.lib.nixosSystem` (not
`nixpkgs.lib.nixosSystem`): the board modules need the `nixos-raspberrypi`
specialArg it injects. `hosts/example-rpi4` is the complete reference. It
evaluates this repo's modules against nixos-raspberrypi's own nixpkgs, on
purpose, so its kernel stays cacheable.

```nix
{
  inputs.nix-config.url = "github:noamsto/nix-config";
  # Follow this flake's input so you get the exact kernel its CI caches.
  inputs.nixos-raspberrypi.follows = "nix-config/nixos-raspberrypi";

  outputs = {nixos-raspberrypi, nix-config, ...}: {
    nixosConfigurations.mypi = nixos-raspberrypi.lib.nixosSystem {
      modules = [
        nix-config.nixosModules.rpi
        {
          hostname = "mypi";
          username = "me";
          nix-config.rpi = {
            board = "rpi4";
            sshAuthorizedKeys = ["ssh-ed25519 AAAA... me@example.invalid"];
          };
        }
      ];
    };
  };
}
```

CI builds `example-rpi4` natively on an `aarch64-linux` runner and pushes it to
`noamsto-nix-config.cachix.org` from `main`. The `nixos-raspberrypi.cachix.org`
cache is in `lib.caches` too.

## Checking

```fish
nix flake check -L
nix fmt
nix eval .#nixosConfigurations.example.config.system.build.toplevel.drvPath
```

`just --list` shows the other recipes.

## Development

Git hooks are run by [prek](https://github.com/j178/prek) and installed for both
commit and push when you enter the dev shell (`nix develop` or direnv). Commits
run formatting and basic checks plus a betterleaks scan of the staged changes;
pushes run a betterleaks scan of the commits being pushed
(`scripts/pre-push-leak-check.sh`). The push check scans every local branch and
tag not yet on the remote, plus HEAD, so a leak on any unpushed ref blocks the
push. A second refspec naming a bare commit sha is not covered. Run
`nix shell nixpkgs#betterleaks nixpkgs#prek -c bash scripts/test-pre-push-leak-check.sh`
to test the push check.

## Caution

- The AI-agent settings under `home/ai/` are tuned for the author's own trust
  model: broad command allowlists, auto-approved MCP servers (including
  Playwright and Firefox DevTools browser servers), and the sandbox disabled
  with all network domains allowed (`home/ai/claude-code/settings.json`). Do not
  copy them blindly.
- `.envrc` runs `use flake . --accept-flake-config`, so `direnv allow` trusts
  the binary caches and keys in `nixConfig` (`flake.nix`, mirrored in
  `lib/caches.nix`). Read them before allowing.

## License

MIT, see [LICENSE](LICENSE).
