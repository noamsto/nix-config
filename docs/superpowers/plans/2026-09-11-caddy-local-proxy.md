# Plan — Caddy reverse proxy module for local services (#242)

Source of truth: `SPEC.md` in this worktree. Three files change; no existing
behaviour is touched.

## Step 1: write `nixos/services/local-proxy.nix`

New module, off by default. Shape follows `nixos/services/jellyfin.nix` (same
directory): `let cfg = config.services.<name>` over a `mkIf cfg.enable` body,
`genAttrs` for the per-interface firewall.

Options (`services.localProxy`):

| option | type | default | note |
| --- | --- | --- | --- |
| `enable` | `mkEnableOption` | off | |
| `hostNames` | `listOf str` | `[config.hostname "localhost"]` | vhost addresses, `http://` prefixed by the module |
| `lanInterfaces` | `listOf str` | `[]` | opens TCP 80 **only**, on these interfaces |
| `services.<name>.upstream` | `str` | `"127.0.0.1"` | |
| `services.<name>.port` | `port` | (required) | |
| `services.<name>.paths` | `listOf str` | `["/${name}"]` | `"/"` claims the root catch-all |
| `services.<name>.streaming` | `bool` | `false` | emits `flush_interval -1` |
| `services.<name>.responseHeaderTimeout` | `nullOr str` | `null` | emits a `transport http` block |

`paths` defaults to `["/${name}"]`, so the submodule must take the
`types.attrsOf (types.submodule ({name, ...}: { options = { ... }; }))` form —
not a bare `submodule { options = ...; }`, which has no `name` in scope.

Generation. Per service, per path, one `handle` block; `"/"` emits `handle`
with no matcher, every other path emits `handle <path>*` — the **prefix glob**
another host's reverse proxy's comment insists on, so a bare `/v1` is proxied as well as `/v1/...`.
`handle` rather than a bare matcher on `reverse_proxy`, because Caddy sorts
`handle` blocks by matcher specificity and evaluates the matcher-less one last,
so the root service cannot swallow another service's paths.

**Source order in the generated Caddyfile is irrelevant** and must not be
engineered. Blocks come out in attrset order, so `houston` (the matcher-less
root) is emitted *before* `lemonade`; the sort that matters happens in Caddy's
Caddyfile adapter, not in the file. Do not try to force emission order — it is
neither achievable through attrset iteration nor needed.

Also set the vhost's `logFormat` explicitly to
`output file ${config.services.caddy.logDir}/access-local-proxy.log`. The
nixpkgs per-vhost default derives the filename from the vhost key, and this key
is four space-separated `http://` addresses, which would produce an ~89-char
mangled log filename.

The proxy body, exactly (the `transport http` wrapper is required —
`response_header_timeout` is a subdirective of `transport`, not of
`reverse_proxy`, per another host's reverse proxy's file):

```
handle /api/v1* {
  reverse_proxy 127.0.0.1:13305 {
    flush_interval -1
    transport http {
      response_header_timeout 300s
    }
  }
}
```

A service with neither knob set emits the bare one-liner
`reverse_proxy <upstream>:<port>` with no block.

Config body:
- `services.caddy.enable = true` and a single
  `virtualHosts.<"http://a http://b ...">.extraConfig` built from `hostNames`.
- `networking.firewall.interfaces = genAttrs cfg.lanInterfaces (_: { allowedTCPPorts = [80]; })`.
- Assertions: at most one service claims `/`; no path claimed by two services.

Comments earn their place — the load-bearing ones, and only these: why the Host
header is **not** rewritten (houston 421s an unknown Host and 403s when Origin
and Host disagree), why prefix globs, why `handle`, and on `lanInterfaces` what
naming an interface actually exposes.

## Step 2: import it

Add `./local-proxy.nix` to the `imports` list in `nixos/services/default.nix`.

## Step 3: register on halo

In `hosts/halo/default.nix`, next to the existing `services.jellyfinHost`
block:

```nix
services.localProxy = {
  enable = true;
  hostNames = [config.hostname "<host>.<tailnet>.ts.net" "<host-ip>" "localhost"];
  services = {
    houston = { port = 9090; paths = ["/"]; streaming = true; responseHeaderTimeout = "300s"; };
    lemonade = {
      port = config.hardware.amd-npu.lemonade.port;
      paths = ["/api/v1" "/api/v0" "/v1" "/v0" "/realtime" "/logs/stream"];
      streaming = true;
      responseHeaderTimeout = "300s";
    };
  };
};
```

Comments: why these four names and not `halo.local` (houston's Host gate), and
why lemonade's UI is not proxied (app-store redirect on phones; and it would
sit same-origin with houston's `Path=/` control cookie). No change to
`hardware.amd-npu.lemonade.allowedOrigins` — Spec Decision 4.

## Step 4: verify (no `switch`)

Invoke the **`nix-rebuild`** skill before running any of these. `git add
nixos/services/local-proxy.nix` first — an untracked file is invisible to the
flake, and a brand-new module is exactly the case that bites. The other two
edited files are already tracked, so their working-tree edits are visible.

1. **Cheap eval of the generated body**, no build:
   `nix eval --raw '.#nixosConfigurations.halo.config.services.caddy.virtualHosts."<the vhost key>".extraConfig'`.
   Read it: every non-root path carries its `*` glob, the root block has no
   matcher, and each `response_header_timeout` sits inside a `transport http`
   block.

2. **Realise the Caddyfile.** Do **not** `nix build` the `configFile` option:
   it is the *string* `"${Caddyfile-formatted}/Caddyfile"`, a sub-path of an
   output, and `nix build` rejects a string whose context is not exactly the
   output placeholder. Build the directory instead:

   ```
   nix build --impure --expr 'builtins.dirOf (builtins.getFlake (toString ./.)).nixosConfigurations.halo.config.services.caddy.configFile'
   ```

   This also runs `caddy fmt` over the file as a side effect of building it.

3. **Check the adapter's route order** — the property the whole design rests
   on. Use the caddy this config actually pins, not the registry's:
   `nix build --no-link --print-out-paths .#nixosConfigurations.halo.config.services.caddy.package`, then

   ```
   <caddy>/bin/caddy adapt --adapter caddyfile --config result/Caddyfile | jq '.apps.http.servers'
   ```

   Assert: the route with **no** path matcher sorts **last**, and longer path
   matchers precede shorter ones. `adapt` rather than `validate` — `validate`
   provisions loggers and an unprivileged run can fail on `/var/log/caddy`
   rather than on anything about this module.

4. `nix build .#nixosConfigurations.halo.config.system.build.toplevel --dry-run`
   (task AC3 — **no `switch`**).

5. `nix fmt`, then commit. alejandra/prettier rewrite files and the **first**
   `git commit` fails; `git add` the reformatted files and re-run the **same**
   commit. statix/deadnix findings are fixed at the source.

## Step 5: PR body

State, per task AC5: halo only and why; prefixes not subdomains and why
(evidence for both apps); `LEMONADE_ALLOWED_ORIGINS` unchanged and why; and the
deliberate deviation on AC4's firewall wording, with the reasoning. Carry over
the accepted risks and the "restart houston on loopback" note from `SPEC.md`.

## Out of scope

No dashboard page, no HTTPS, no `handle_path`/prefix stripping, no change to
houston, not enabled on any other host.

Two things that look like gaps and are not, so nobody "fixes" them:

- **No `mkMerge` plumbing for the firewall.** `services.jellyfinHost` already
  writes `networking.firewall.interfaces.<iface>.allowedTCPPorts` on halo; list
  options concatenate across definitions, so a shared interface simply ends up
  with both port sets.
- **Assertions do not catch prefix shadowing** (`/logs` vs `/logs/stream`),
  only exact duplicates. Caddy's longest-matcher-first sorting makes shadowing
  benign; leave the assertion set as it is.
