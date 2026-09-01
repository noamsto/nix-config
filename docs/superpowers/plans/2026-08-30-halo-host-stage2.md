# Halo Host — Stage 2 (workloads) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the bootable `halo` base into the machine it was designed to be — an LLM inference server reachable from the ThinkPads, a podman host, and a Steam machine that is simply *there* when the TV switches to its HDMI input.

**Architecture:** The LLM stack is `hardware.amd-npu` from the `nix-amd-ai` flake input this repo already uses on g6 — it has gfx1151 prebuilts and measured Strix Halo memory settings, so halo consumes existing work rather than duplicating it. Steam runs as an always-up gamescope session under greetd autologin, and gamemode arbitrates GPU memory between games and inference.

**Tech Stack:** NixOS, `nix-amd-ai` (`hardware.amd-npu`, lemonade/lemond), `programs.steam.gamescopeSession`, greetd, gamemode, Sunshine, podman.

**Prerequisites:** Stage 1 complete and installed — `docs/superpowers/plans/2026-08-30-halo-host-stage1.md`, in particular Task 8 (GTT confirmed) and Task 9 (HDMI hot-plug behaviour characterised). **Task 6 below depends on the Task 9 finding**; everything else can proceed without it.

**Spec:** `docs/superpowers/specs/2026-08-29-halo-host-design.md` — note that the spec's "LLM stack" section calls for a bespoke `llama-cpp` unit. **That is superseded by this plan**; see Task 2's rationale.

---

## Context an engineer needs before starting

The three Stage 1 conventions still apply: **pre-commit hooks reformat on the first commit** (re-`git add` and re-run the same commit), **Nix only sees git-tracked files** (`git add` before evaluating), and work happens in a worktree, not on `main`.

**Two Stage 1 decisions that constrain this plan:**

1. **`programs.steam` is behind `desktop.isEnabled`.** Stage 1 gated `nixos/desktop/default.nix` on `config.desktop.isEnabled` to fix a flatpak/portal assertion, and halo is `desktop.mode = "none"`. So halo cannot inherit Steam from that module and must enable it directly. This is arguably more correct anyway: that block configures desktop-session Steam, whereas halo runs gamescope directly on DRM.

2. **`boot.extraModprobeConfig` already sets the ttm limits.** Task 2 moves that to `hardware.amd-npu.gpuMemory`, and **the Stage 1 block must be deleted in the same commit** — two modules emitting `options ttm …` is a conflict, not a merge.

**Why `hardware.amd-npu` rather than a hand-rolled llama.cpp unit:** the `nix-amd-ai` input carries gfx1151 (Strix Halo) prebuilts, a `gpuTarget` option that already knows this chip, measured GTT values for a 128 GB Halo, and a lemonade server that spawns `llama-server` for you. g6 already runs it. Writing a separate `llama-server` unit would mean maintaining two LLM setups and re-deriving what that repo measured. The cost is real — it builds from source, which is why g6 rebuilds are slow — and that cost is accepted deliberately.

---

## File structure

| File | Responsibility |
|---|---|
| `hosts/halo/default.nix` | *Modify.* Everything host-specific: `hardware.amd-npu`, Steam, greetd, gamemode, Sunshine. Stage 1 left this small; it stays the single place halo's identity lives. |
| `hosts/halo/containers.nix` | *Create.* podman services, kept out of `default.nix` so the service list can grow without the host entry point becoming a dumping ground. |

Everything else is host-local configuration; no shared modules should need to change. **If you find yourself editing a file under `nixos/`, stop and report it** — Stage 1 already made the two shared changes this host needed, and a third suggests something is being solved in the wrong place.

---

## Task 1: Storage for models and games

**Files:** Modify `hosts/halo/default.nix`

Stage 1's disko created `/var/lib/models` and `/var/lib/games` as `root:root 0755`. Nothing can write to them yet.

- [ ] **Step 1: Verify the current state**

On `halo`:

```bash
ls -ld /var/lib/models /var/lib/games
```

Expected: both owned `root:root`, mode `0755`.

- [ ] **Step 2: Add tmpfiles rules**

In `hosts/halo/default.nix`:

```nix
  # disko creates these as root:root; the subvolumes exist so large files stay
  # uncompressed and out of any snapshot policy. The models subdirectories are
  # split by consumer: lemond's two caches (Task 2b) and the plain GGUFs
  # ds4-server reads (Task 4b).
  systemd.tmpfiles.rules = [
    "d /var/lib/models 0755 noams users -"
    "d /var/lib/models/hf 0755 noams users -"
    "d /var/lib/models/lemonade 0755 noams users -"
    "d /var/lib/models/gguf 0755 noams users -"
    "d /var/lib/games 0755 noams users -"
  ];
```

`/var/lib/models` carries the btrfs `nodatacow` flag (`chattr +C`, PR #192), and
new subdirectories inherit it — so these are created with CoW already off, which
is what keeps large weights from fragmenting.

Use whatever user `hardware.amd-npu.lemonade.user` is set to in Task 2 — if that is `noams`, use `noams users` for both lines rather than inventing a `lemonade` user.

- [ ] **Step 3: Rebuild and verify**

```bash
sudo nixos-rebuild switch --flake .#halo
ls -ld /var/lib/models /var/lib/games
```

Expected: ownership matches the rules.

- [ ] **Step 4: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): own the models and games subvolumes"
```

---

## Task 2: LLM stack via hardware.amd-npu

**Files:** Modify `hosts/halo/default.nix`

- [ ] **Step 1: Read the reference material first**

Two documents in the `nix-amd-ai` source define what is known about this hardware. Find the store path with:

```bash
nix eval --raw .#nixosConfigurations.halo._module.args.inputs.nix-amd-ai.outPath
```

Then read `docs/halo-bringup-checklist.md` and the README's "GPU memory headroom" section. Do not proceed on memory of this plan alone — those files carry measured values and caveats that supersede general Halo advice found online.

- [ ] **Step 2: Add the module configuration**

In `hosts/halo/default.nix`:

```nix
  hardware.amd-npu = {
    enable = true;
    gpuTarget = "gfx1151"; # Strix Halo; the module default is gfx1150 (Strix Point)
    enableNPU = true;
    enableROCm = true;
    enableVulkan = true;
    enableLemonade = true;
    lemonade.user = "noams";

    # Measured on a 128 GB Halo: pages_limit alone yields exactly 96 GiB of GTT
    # (mem_info_gtt_total = 103079215104). Deliberately no amdgpu.gttsize —
    # ROCm#5595 warns against setting it alongside pages_limit.
    gpuMemory = {
      ttmSizeGiB = 96;
      pagePoolSizeGiB = 96;
    };
  };
```

- [ ] **Step 3: DELETE the Stage 1 modprobe block**

In the same file, remove this entire block — `hardware.amd-npu.gpuMemory` now emits it, and having both means two `options ttm` lines:

```nix
  boot.extraModprobeConfig = ''
    options ttm pages_limit=25165824 page_pool_size=25165824
  '';
```

Keep the surrounding comment's substance by moving it to the `gpuMemory` block, as shown in Step 2.

- [ ] **Step 4: Verify there is exactly one ttm directive**

```bash
nix eval --raw .#nixosConfigurations.halo.config.boot.extraModprobeConfig
```

Expected: exactly one line containing `options ttm pages_limit=25165824 page_pool_size=25165824`. There will also be an unrelated `v4l2loopback` line from `nixos/core/pc.nix` — that one is expected. **If `ttm` appears twice, Step 3 was not done.**

- [ ] **Step 5: Build**

```bash
nix build .#nixosConfigurations.halo.config.system.build.toplevel --no-link
```

Expected: PASS. This will take a long time — `nix-amd-ai` builds from source. Check `https://nix-amd-ai.cachix.org` is in the substituters (it is, in `flake.nix` `nixConfig`) before assuming a long build is unavoidable.

- [ ] **Step 6: Switch and verify the service is up**

```bash
sudo nixos-rebuild switch --flake .#halo
systemctl status lemond
curl -s http://localhost:13305/api/v1/health
```

Expected: `lemond` active, health endpoint responds.

- [ ] **Step 7: Verify the GPU memory ceiling actually applied**

```bash
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

Expected: `103079215104` (96 GiB exactly). This is the same check as Stage 1 Task 8 — re-run it here because the mechanism changed from a kernel parameter to a modprobe option, and a silent regression would only show up as models failing to load later.

- [ ] **Step 8: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): serve inference via hardware.amd-npu"
```

---

## Task 2b: Redirect lemond's caches onto the models subvolume

**Files:**
- Modify (upstream, `nix-amd-ai`): `modules/amd-npu.nix`, `flake.nix`
- Modify: `flake.lock`, `hosts/halo/default.nix`

`lemond` runs as a normal user and inherits the default HuggingFace cache
location, so weights land in `~/.cache/*` regardless of who owns
`/var/lib/models`. On g6 that is **147 GB in `~/.cache/huggingface` plus 9.9 GB
in `~/.cache/lemonade`**. On halo `/home` is `compress=zstd` and CoW — the two
things `@models` exists to avoid.

Fix it upstream, not with a local unit override. The module owns the `lemond`
unit; poking `systemd.services.lemond.environment` from `hosts/halo/` would
break silently if upstream renamed anything, and g6 wants the same option.

- [ ] **Step 1: Branch in the existing nix-amd-ai clone**

The repo is already cloned at `/home/noams/git/noamsto/nix-amd-ai` (note: not
under `~/Data/git`, where nix-config lives). Its worktrees go in
`nix-amd-ai-worktrees/`.

```bash
cd /home/noams/git/noamsto/nix-amd-ai
wt switch -c feat/lemonade-cache-dir
```

Read `AGENTS.md` there before committing — that repo is squash-only with
`squash_message = COMMIT_MESSAGES`, and requires `Co-authored-by:` trailers in
branch commits (not the PR body) for carried work. Its bring-up notes for this
chip are in `docs/` — see the Strix Halo (gfx1151) checklist added in #99.

- [ ] **Step 2: Determine the real env var names**

Do not guess these. `HF_HOME` is standard for `huggingface_hub`, and the
`lemond` launcher contains a `LEMONADE_CACHE_D…` string next to a
`/.cache/lemonade` default, but the launcher is stripped and the spelling was
not confirmable from it. Confirm both against upstream before writing the
option:

```bash
rg -n 'LEMONADE_CACHE|HF_HOME|HF_HUB_CACHE' $(nix eval --raw .#lemonade.src)
```

Expected: the exact variable names lemonade reads. If `LEMONADE_CACHE_DIR` is
not what it is called, use the name you found in Step 3 — do not ship the
guess.

- [ ] **Step 3: Write the failing check**

In `flake.nix`, beside the existing `module-eval-*` checks, add one that sets
the option that does not exist yet:

```nix
            module-eval-cachedir =
              (inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  inputs.self.nixosModules.default
                  {
                    boot.loader.grub.enable = false;
                    fileSystems."/" = {
                      device = "/dev/sda1";
                      fsType = "ext4";
                    };
                    hardware.amd-npu = {
                      enable = true;
                      enableLemonade = true;
                      lemonade.user = "testuser";
                      lemonade.cacheDir = "/var/lib/models";
                    };
                    users.users.testuser = {
                      isNormalUser = true;
                      extraGroups = ["video" "render"];
                    };
                  }
                ];
              }).config.system.build.etc;
```

- [ ] **Step 4: Run the check to verify it fails**

```bash
nix build .#checks.x86_64-linux.module-eval-cachedir
```

Expected: FAIL — `The option 'hardware.amd-npu.lemonade.cacheDir' does not exist`.

- [ ] **Step 5: Add the option**

In `modules/amd-npu.nix`, inside the `lemonade` option block:

```nix
      cacheDir = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/var/lib/models";
        description = ''
          Root for lemond's model caches, pointing `HF_HOME` and lemonade's own
          cache at a dedicated location instead of the service user's home.

          A host with a subvolume tuned for weights (uncompressed, nodatacow)
          needs this: lemond runs as a normal user and would otherwise fill
          `~/.cache` — 157 GB on a host that has been serving for a while.

          A runtime path, deliberately a string so it is not copied into the Nix
          store. The directory and its `hf`/`lemonade` subdirectories must exist
          and be writable by `user`; the unit does not create them, since it is
          typically a mountpoint the host manages.
        '';
      };
```

- [ ] **Step 6: Wire it into the unit**

In the `systemd.services.lemond.environment` attrset, alongside the other
`optionalAttrs` blocks:

```nix
        // optionalAttrs (cfg.lemonade.cacheDir != null) {
          HF_HOME = "${cfg.lemonade.cacheDir}/hf";
          LEMONADE_CACHE_DIR = "${cfg.lemonade.cacheDir}/lemonade";
        }
```

Substitute whatever Step 2 established if the names differ.

- [ ] **Step 7: Run the check to verify it passes**

```bash
nix build .#checks.x86_64-linux.module-eval-cachedir
nix flake check
```

Expected: both succeed, and no existing check regresses.

- [ ] **Step 8: Commit and open the PR**

```bash
git add modules/amd-npu.nix flake.nix
git commit -m "feat(lemonade): add cacheDir to relocate model caches off \$HOME"
git push -u origin feat/lemonade-cache-dir
gh pr create --assignee @me --title "feat(lemonade): add cacheDir to relocate model caches off \$HOME" --body "..."
```

- [ ] **Step 9: Bump the lock here and set the option**

Once that PR merges, back in `nix-config`:

```bash
nix flake update nix-amd-ai
```

Then in `hosts/halo/default.nix`, inside the `lemonade` block from Task 2:

```nix
      cacheDir = "/var/lib/models";
```

- [ ] **Step 10: Commit**

```bash
git add flake.lock hosts/halo/default.nix
git commit -m "feat(halo): keep model caches on the models subvolume"
```

---

## Task 3: Expose inference on the tailnet

**Files:** Modify `hosts/halo/default.nix`

By default `lemonade.host` is `localhost`, which is useless to the ThinkPads.

- [ ] **Step 1: Bind to the tailnet and set origins**

The module warns if `host` is non-loopback while `allowedOrigins` is empty — browsers on other machines get a 403. Add to the `hardware.amd-npu` block:

```nix
    lemonade = {
      user = "noams";
      host = "0.0.0.0";
      allowedOrigins = ["http://halo:13305" "http://100.64.0.0:13305"];
    };
```

Replace the second origin with halo's actual Tailscale IP once known (`tailscale ip -4` on the host). Binding `0.0.0.0` is safe here only because the firewall is closed by default and `tailscale0` is a trusted interface (`nixos/services/tailscale.nix`) — **do not add a `networking.firewall.allowedTCPPorts` entry for 13305**, which would expose it to the LAN.

The firewall is the *only* thing in front of an otherwise unauthenticated
endpoint. If that ever stops being enough — a device you do not control joins
the tailnet, or a subnet route is added — `lemond` reads `LEMONADE_API_KEY` and
`LEMONADE_ADMIN_API_KEY`, so a key can be supplied through agenix without
redesigning the exposure. Not needed for the first deploy; noted so the option
is known.

- [ ] **Step 2: Verify no eval warning**

```bash
nix build .#nixosConfigurations.halo.config.system.build.toplevel --no-link 2>&1 | grep -i "allowedOrigins"
```

Expected: no output. Any warning here means the origins list did not take.

- [ ] **Step 3: Switch, then verify from a ThinkPad**

On `halo`: `sudo nixos-rebuild switch --flake .#halo`

From g6, over the tailnet:

```bash
curl -s http://halo:13305/api/v1/health
```

Expected: a healthy response. If it hangs, check `sudo tailscale status` on both ends before touching the firewall.

- [ ] **Step 4: Verify it is NOT reachable off-tailnet**

From a device on the LAN but not the tailnet, or by using halo's LAN IP rather than its tailnet name:

```bash
curl -s --max-time 5 http://<halo-lan-ip>:13305/api/v1/health
```

Expected: connection refused or timeout. **A response here is a security problem** — the inference API would be exposed to the local network. Stop and fix the firewall before continuing.

- [ ] **Step 5: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): reach inference over the tailnet"
```

---

## Task 4: Declarative model set

**Files:** Modify `hosts/halo/default.nix`

- [ ] **Step 1: See what the registry offers**

```bash
lemonade list
```

- [ ] **Step 2: Declare the models**

`lemonade.models` pulls through a running `lemond` via the `lemond-models` unit. Add inside the `lemonade` block:

```nix
      models = [
        "Qwen3.5-0.8B-FP16-vLLM" # smallest real model; used by the Task 8 vLLM smoke test
      ];
```

Add the larger models you actually intend to serve once Task 8's benchmarks tell you which backend wins. Do **not** set `pruneUnlistedModels = true` yet — the module refuses it against an empty list, and against a short list it deletes everything else you have downloaded.

- [ ] **Step 3: Switch and verify the pull**

```bash
sudo nixos-rebuild switch --flake .#halo
systemctl status lemond-models
ls -la /var/lib/models/hf
du -sh /home/noams/.cache/huggingface 2>/dev/null
```

Expected: the unit succeeded, the model is under `/var/lib/models/hf`, and the
home cache is absent or unchanged. **This expectation only holds once Task 2b is
done** — without the redirect `lemond` writes to `~/.cache/huggingface` no matter
who owns the subvolume, and the models land on the compressed CoW `@home`
instead. If you see the home cache growing, stop and finish Task 2b.

- [ ] **Step 4: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): declare the served model set"
```

---

## Task 4b: Serve DeepSeek-V4-Flash via ds4-server

**Files:** Modify `hosts/halo/default.nix`

`hardware.amd-npu.ds4` is a sibling of `lemonade`, not nested under it, so this
is a second independent server. `pkgs.ds4` already defaults to
`gpuTarget = "gfx1151"` — it was built for this chip — and the unit sets its own
`SupplementaryGroups = ["video" "render"]`, so no user change is needed beyond
what Task 2 already did for `lemond`.

Defaults do not collide: `lemond` listens on 13305, `ds4-server` on 8000.

- [ ] **Step 1: Fetch the GGUF first**

Nothing provisions `ds4.model`. `lemonade.models` has the `lemond-models`
reconcile unit; `ds4` has no equivalent, so an enabled unit with a missing file
restart-loops every 5 s. Fetch it before enabling anything, onto the subvolume:

```bash
ssh halo
cd /var/lib/models/gguf
curl -L -o DeepSeek-V4-Flash.gguf '<release URL for the quant you want>'
ls -lh /var/lib/models/gguf/DeepSeek-V4-Flash.gguf
```

Expected: the file exists and is non-zero. Pick the quant that fits the 96 GiB
GTT window with context to spare.

- [ ] **Step 2: Enable the unit**

In `hosts/halo/default.nix`, inside `hardware.amd-npu`, as a sibling of the
`lemonade` block:

```nix
    ds4 = {
      enable = true;
      user = "noams";
      model = "/var/lib/models/gguf/DeepSeek-V4-Flash.gguf";
      host = "0.0.0.0";
      # SSD-streaming KV lands in the unit's StateDirectory (/var/lib/ds4),
      # which is on the compressed root subvolume, not @models.
      extraArgs = ["--ssd-streaming" "--kv-disk-dir" "/var/lib/ds4/server-kv"];
    };
```

Leave `port` unset — 8000 is the default and does not clash with lemond.

- [ ] **Step 3: Switch and verify**

```bash
sudo nixos-rebuild switch --flake .#halo
systemctl status ds4-server
curl -s http://halo:8000/v1/models
```

Expected: the unit is `active (running)` and the endpoint lists the model. If it
is restart-looping, check `journalctl -u ds4-server` for a missing-model path
before anything else.

- [ ] **Step 4: Confirm it is not reachable from the LAN**

```bash
curl -s --max-time 5 http://<halo-lan-ip>:8000/v1/models
```

Expected: timeout. Port 8000 must never enter `allowedTCPPorts`, same rule as
13305 in Task 3.

- [ ] **Step 5: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): serve DeepSeek-V4-Flash via ds4-server"
```

---

## Task 5: Steam as an always-up gamescope session

**Files:** Modify `hosts/halo/default.nix`

Recall from the Context section: halo cannot inherit `programs.steam` from `nixos/desktop/default.nix`, because that module is gated on `desktop.isEnabled`.

- [ ] **Step 1: Enable Steam and the gamescope session**

```nix
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };
```

- [ ] **Step 2: Autologin into that session with greetd**

`programs.steam.gamescopeSession` installs a `steam-gamescope` binary and a `steam` Wayland session. greetd is used rather than SDDM because halo has no desktop environment to log into:

```nix
  services.greetd = {
    enable = true;
    settings.initial_session = {
      command = "${pkgs.steam}/bin/steam-gamescope";
      user = "noams";
    };
  };
```

Verify the binary path before committing — if `steam-gamescope` is not at that location, find it with `nix eval --raw .#nixosConfigurations.halo.config.programs.steam.package` and inspect. **Do not guess the path**; a wrong `command` fails at boot with no display attached to debug it from.

- [ ] **Step 3: Build**

```bash
nix build .#nixosConfigurations.halo.config.system.build.toplevel --no-link
```

Expected: PASS. If it fails on a display-manager conflict, something else is enabling one — find it rather than forcing greetd on top.

- [ ] **Step 4: Switch and verify on the TV**

```bash
sudo nixos-rebuild switch --flake .#halo
sudo systemctl restart greetd
```

Expected: Big Picture appears on the TV.

- [ ] **Step 5: Verify the whole point of the design**

Power the TV off, wait a minute, power it back on and switch to halo's input.

Expected: Big Picture is there, with no interaction. **This is the requirement the entire session design exists to satisfy** — if it fails, Task 6 is what fixes it, so continue rather than redesigning here.

- [ ] **Step 6: Verify inference survived**

From g6: `curl -s http://halo:13305/api/v1/health`

Expected: still healthy. An idle Steam session must not disturb the server.

- [ ] **Step 7: Point Steam at the games subvolume**

In the Steam UI: Settings → Storage → add `/var/lib/games` and make it the default library. Steam's default is `~/.local/share/Steam`, which would put games on `@home` and inside any snapshot policy. This is a UI setting, not something the Nix config asserts.

- [ ] **Step 8: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): boot into a gamescope steam session"
```

---

## Task 6: Survive the TV being off

**Files:** Modify `hosts/halo/default.nix`

**This task is conditional on Stage 1 Task 9's finding.**

- If Task 9 found the HDMI connector stays `connected` with the TV off or on another input, **and Task 5 Step 5 passed**, there is nothing to do. Record that and skip to Task 7.
- If the connector drops, or Task 5 Step 5 failed, continue.

- [ ] **Step 1: Confirm the failure mode**

With the TV off:

```bash
systemctl status greetd
for c in /sys/class/drm/card*-HDMI*; do echo "$c: $(cat $c/status)"; done
```

Record whether greetd failed and what the connector status is.

- [ ] **Step 2: Force the connector**

Substitute the connector name and the TV's native resolution from Stage 1 Task 9:

```nix
  # The TV drops HDMI hot-plug detect when off or on another input, so the
  # session has no display to start on at boot. Forcing the connector keeps it
  # present regardless of what the TV is doing.
  boot.kernelParams = ["video=HDMI-A-1:1920x1080@60e"];
```

- [ ] **Step 3: Rebuild, reboot with the TV OFF, then turn it on**

```bash
sudo nixos-rebuild switch --flake .#halo
sudo reboot
```

Leave the TV off across the reboot. Then power it on and switch to halo's input.

Expected: Big Picture is present.

- [ ] **Step 4: If it still fails, add the restart backstop**

```nix
  systemd.services.greetd.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };
```

Re-run Step 3.

- [ ] **Step 5: If it STILL fails, the TV's EDID is unreadable while off**

Capture the EDID while the TV is on:

```bash
cp /sys/class/drm/card*-HDMI-A-1/edid /tmp/tv-edid.bin
```

Then supply it via `hardware.display.edid.packages` / `drm.edid_firmware`. Report before implementing — this path adds a binary blob to the repo and deserves a decision rather than a silent commit.

- [ ] **Step 6: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "fix(halo): keep the HDMI connector present when the TV is off"
```

---

## Task 7: Hand the GPU to games, and take it back

**Files:** Modify `hosts/halo/default.nix`

An idle Steam session is harmless, but a running game and a loaded model both want the unified pool.

- [ ] **Step 1: Confirm the contention is real before solving it**

With a model loaded, launch a game and watch:

```bash
systemctl status lemond
cat /sys/class/drm/card*/device/mem_info_gtt_used
```

Record whether the game launches cleanly with the model resident. **If there is no problem, say so and skip this task** — on 128 GB there may genuinely be room for both, and an unnecessary stop/start of the inference server is worse than nothing.

- [ ] **Step 2: Add the gamemode hooks**

```nix
  programs.gamemode = {
    enable = true;
    settings.custom = {
      # A game and a loaded model both draw from the same unified pool. This
      # fires on game launch, not session start, so the model stays served the
      # whole time the TV is off.
      start = "${pkgs.systemd}/bin/systemctl stop lemond";
      end = "${pkgs.systemd}/bin/systemctl start lemond";
    };
  };
```

- [ ] **Step 3: Verify gamemode is actually engaged**

Not every game triggers gamemode on its own. In Steam, set the game's launch options to `gamemoderun %command%`, then with the game running:

```bash
gamemoded -s
systemctl is-active lemond
```

Expected: gamemode reports active, `lemond` reports `inactive`.

- [ ] **Step 4: Verify it comes back**

Quit the game, then:

```bash
systemctl is-active lemond
curl -s http://localhost:13305/api/v1/health
```

Expected: active and healthy within a few seconds.

- [ ] **Step 5: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): stop inference while a game is running"
```

---

## Task 8: Stream to the ThinkPads

**Files:** Modify `hosts/halo/default.nix`

- [ ] **Step 1: Enable Sunshine**

`capSysAdmin` is required for the KMS capture grab on Wayland:

```nix
  services.sunshine = {
    enable = true;
    capSysAdmin = true;
    openFirewall = true;
  };
```

`openFirewall` is acceptable here because the firewall's trusted interface is `tailscale0`; verify in Step 3 that this did not open Sunshine to the LAN.

- [ ] **Step 2: Switch and pair**

```bash
sudo nixos-rebuild switch --flake .#halo
systemctl --user status sunshine
```

Open `https://halo:47990` from a ThinkPad to set credentials and pair Moonlight.

- [ ] **Step 3: Verify the LAN exposure**

```bash
sudo nmap -p 47984-48010 <halo-lan-ip>
```

If the ports are open to the LAN and you do not want that, replace `openFirewall = true` with explicit `networking.firewall.interfaces."tailscale0".allowedTCPPorts`. Record which you chose and why.

- [ ] **Step 4: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): stream games to the thinkpads"
```

---

## Task 9: Container services

**Files:** Create `hosts/halo/containers.nix`, modify `hosts/halo/default.nix`

- [ ] **Step 1: Create the module**

```nix
# Background services for halo. Kept separate from default.nix so this list can
# grow without the host entry point becoming a dumping ground.
{
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {};
  };
}
```

- [ ] **Step 2: Import it**

Add `./containers.nix` to the `imports` list in `hosts/halo/default.nix`.

- [ ] **Step 3: Build**

```bash
git add hosts/halo/containers.nix
nix build .#nixosConfigurations.halo.config.system.build.toplevel --no-link
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add hosts/halo
git commit -m "feat(halo): scaffold container services"
```

This deliberately ships an empty container set. **Do not invent services to fill it** — add them when there is an actual service to run, each as its own commit.

---

## Task 10: Close nix-amd-ai's vLLM question (their Phase 2)

The `nix-amd-ai` repo states plainly in `pkgs/vllm-rocm/sources.nix` that **no gfx1151 kernel has ever executed** — packaging is verified, but nothing has run. Their checklist calls this "the cheapest high-value result on the list", and halo is the only hardware that can answer it.

This task works in the **`nix-amd-ai` repo**, not this one.

- [ ] **Step 1: Enable vLLM**

In `hosts/halo/default.nix`, inside `hardware.amd-npu`:

```nix
    enableVllm = true;
```

The module asserts this requires `enableROCm` and `enableLemonade`, both already set. Rebuild and switch.

- [ ] **Step 2: Run the smallest real model end to end**

```bash
lemonade pull Qwen3.5-0.8B-FP16-vLLM
lemonade run Qwen3.5-0.8B-FP16-vLLM
```

Expected: one successful completion. **That single result closes the "never executed" caveat.** Capture the full output.

- [ ] **Step 3: Prove it is not only toy-sized**

```bash
lemonade pull Qwen3.5-9B-FP16-vLLM
lemonade run Qwen3.5-9B-FP16-vLLM
```

- [ ] **Step 4: Check the pin before drawing conclusions**

Their checklist notes the vllm pin is stale and moves once their #95 lands. If a newer tag is available with both gfx1150 and gfx1151 builds, prefer testing that over the current pin — a failure on a stale pin is not evidence about the current one.

- [ ] **Step 5: Report upstream**

Update the caveat comment in `pkgs/vllm-rocm/sources.nix` and comment on issues #63 and #68 with the actual output. Commit in that repo, not this one.

---

## Task 11: The decisive ROCm vs Vulkan A/B (their Phase 3)

Their issue #61 is gated on one question, and it is **not** "is ROCm faster" — the gfx1150 answer was no. It is: *does the ordering flip at long context on gfx1151?* Community data suggests HIP+rocWMMA+FA holds ~51 t/s at 8K where Vulkan collapses to ~32 t/s.

- [ ] **Step 1: Fix the tooling gap FIRST**

Their harness has a documented flaw: `-ctx-size` **only reaches `llama-server` in `--mtp-ab` mode** (consumed by `BuildLlamaServerArgs` at `internal/bench/run.go:571`, inside `RunMTPAB`). On the normal `-backend` path, lemond spawns `llama-server` with whatever the config says — so a long `-prompt-tokens` against a 2048 context **silently truncates and still reports healthy numbers**. That is the failure mode that would make this entire phase worthless.

Set the context declaratively instead, in `hosts/halo/default.nix`:

```nix
    lemonade.settings.llamacpp.args = "--ctx-size 32768 --flash-attn on";
```

- [ ] **Step 2: Confirm the server actually got the context**

```bash
journalctl -u lemond | grep -i "ctx-size"
```

Expected: the spawned `llama-server` argv contains `--ctx-size 32768`. **Do not run a single benchmark until this is confirmed.**

- [ ] **Step 3: Confirm rocWMMA is ON for gfx1151**

Their table is explicit and the sign is arch-dependent:

| target | rocWMMA |
|---|---|
| gfx1150 | **OFF** — measured net regression, −42% pp4096 |
| gfx1151 | **ON** — this is where the community win comes from |

Do not carry the gfx1150 conclusion over. The comparison is only fair with rocWMMA ON, Flash-Attention, and hipBLASLt.

- [ ] **Step 4: Run the A/B at long context**

From a `nix-amd-ai` checkout:

```bash
nix run .#benchmark -- -backend rocm   -prompt-tokens 8192 -repeat 5 -no-tui
nix run .#benchmark -- -backend vulkan -prompt-tokens 8192 -repeat 5 -no-tui
```

Repeat at 16K and 32K. **Do not bench pp512/tg128** — short context was already answered on gfx1150 and is not the regime that motivates Halo.

- [ ] **Step 5: Capture GPU utilisation alongside**

Same as their gfx1150 evaluation did, to rule out CPU fallback. `-min-decode-tps` guards only the gross case.

- [ ] **Step 6: Log the raw output**

Write results under `bench-logs/` in the `nix-amd-ai` repo — that is their convention.

- [ ] **Step 7: Act on the decision gate**

If ROCm+rocWMMA clearly wins long context, their checklist calls for vendoring a per-arch gfx1151 build. Set `hardware.amd-npu` on halo to whichever backend won, and record the numbers in this repo's spec.

---

## Task 12: Reconcile the spec and open the PR

**Files:** Modify `docs/superpowers/specs/2026-08-29-halo-host-design.md`

- [ ] **Step 1: Correct the LLM section**

The spec calls for a bespoke `llama-cpp` unit with `vulkanSupport`. Replace that with what was actually built — `hardware.amd-npu` — and say why: the input already carries gfx1151 prebuilts and measured Halo memory values, and g6 already runs it.

- [ ] **Step 2: Record the benchmark results**

Add the Task 11 numbers and the resulting backend choice. This closes the spec's open item 3 ("Vulkan vs. ROCm benchmark").

- [ ] **Step 3: Record what the couch experience is actually like**

The spec argued Jovian was not worth it at a 90/10 split, and predicted the losses would not matter on a wall-powered desktop. Now that it has been used, say whether that held. **If it did not, say so plainly** — that is the finding that would justify revisiting Jovian, and a spec that only records correct predictions is worthless.

- [ ] **Step 4: Commit and open the PR**

```bash
git add docs/superpowers/specs/2026-08-29-halo-host-design.md
git commit -m "docs(halo): reconcile the spec with what stage 2 built"
git push -u origin <branch>
gh pr create --assignee @me --title "feat(halo): stage 2 — inference, steam session, services" --body "..."
```

---

## Definition of done

- `curl http://halo:13305/api/v1/health` succeeds from a ThinkPad over the tailnet, and fails from the LAN.
- `mem_info_gtt_total` reads `103079215104`, with exactly one `options ttm` directive in the modprobe config.
- Turning the TV on and switching to halo's input shows Big Picture, with no interaction and no keyboard.
- Inference is still healthy after the Steam session has been idle, and recovers automatically after a game exits.
- Moonlight connects from a ThinkPad.
- `nix-amd-ai` issues #61, #63, and #68 have real data attached, and `bench-logs/` has the raw output.
