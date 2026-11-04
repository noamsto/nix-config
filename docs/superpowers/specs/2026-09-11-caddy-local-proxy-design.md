# Spec — Caddy reverse proxy module for local services (nix-config #242)

## Problem

houston and lemonade each listen on their own port and are reached from a phone
over Tailscale. Every service means another port to remember and retype. One
HTTP entry point per machine replaces that.

## Evidence (all four open questions resolved from source)

### Hosts that exist

`lib/host-configs.nix` + `hosts/`: `halo`, `thinkpad-p14s-g5`,
`thinkpad-p14s-g6`, `mbp-m4-pro`, `installer`.

- `halo` — `serverMode = true`, headless under the TV, never moves, runs
  `lemond` (`hardware.amd-npu.lemonade`, port 13305) and runs the agents.
  Confirmed live on this box: `hostname` is `halo`, `lemond` listening on
  `0.0.0.0:13305`, and `houston` listening on `<host-ip>:9090` — the
  tailnet address, **not** loopback (see Accepted risks).
- `thinkpad-p14s-g6` — `serverMode = true`, but `lib/host-configs.nix` says
  "Temporarily running g6 as an always-on headless server". It is a laptop that
  roams onto untrusted wifi.
- `thinkpad-p14s-g5` — work laptop, roams. `mbp-m4-pro` — nix-darwin.

### houston cannot live under a path prefix

From `~/git/houston`:

- `ui/dist/index.html` emits **absolute** asset URLs (`/assets/index-*.js`,
  `/favicon.svg`); the SPA fetches **absolute** `/api/...`; `ui/vite.config.ts`
  sets no `base`.
- `server/server.go` mounts exactly `/` (SPA) and `/api/`. There is no
  `/api/v1`.
- `server/hosts.go` enforces a Host allowlist — `localhost`, `127.0.0.1`,
  `::1`, `os.Hostname()`, tailnet (100.64/10) addresses and their
  reverse-resolved MagicDNS names, plus `-hostname` values. Anything else gets
  **421** before any handler runs.
- `server/auth.go` compares `Origin` against `r.Host`, so a proxy that
  **rewrites** the upstream Host breaks `/api/` with **403 forbidden origin**.

So houston must sit at the **root** of a hostname its own gate already knows,
with the Host header **preserved**.

### lemonade's web UI is useless through a proxy; its API is not

From the bundle `lemond` actually serves
(`/nix/store/djmn58mxn17vacq8f0wv7asig71vnh5l-lemonade-web-app-11.9.0/`):

- The entry module, unconditionally on load, does
  `/android/i.test(ua) ? location.href = "https://play.google.com/store/apps/details?id=com.lemonade.mobile.chat.ai"
  : /iPad|iPhone|iPod/.test(ua) && !window.MSStream ? location.href = "https://apps.apple.com/..."
  : createRoot(...).render(...)`.
  **On a phone the page bounces to an app store before it renders.** The stated
  problem is retyping a port *on the phone*, so proxying this UI does not serve
  the goal.
- In web-app mode `serverConfig.initialize()` sets the API base to
  `window.location.origin` — **origin only, path dropped** — so
  `getApiBaseUrl()` is `<origin>/api/v1` and websockets are built at the origin
  root: `/logs/stream`, `/realtime`, `/v1/realtime`.

**lemond's real route roots, probed against the live server on this box** (not
inferred from the bundle, since Decision 3 takes the bundle's client out of
scope). `lemond` serves JSON on four API roots and falls through to its own web
bundle for everything else:

| probe | result |
| --- | --- |
| `/api/v1/health`, `/api/v1/models`, `/api/v1/stats`, `/api/v1/system-info` | JSON |
| `/api/v0/health`, `/v0/models`, `/v1/models`, `/v1/health` | JSON |
| `/api/v1/chat/completions`, `/v1/chat/completions` | JSON (405 on GET, POST route) |
| `/api/health`, `/api/v1/models/` | JSON error, "endpoint does not exist" |
| `/health`, `/logs/stream`, `/ws`, `/docs` | lemond's **web bundle**, not JSON |

So the API roots are `/api/v1`, `/api/v0`, `/v1` and `/v0`. `/health` is *not*
a lemond route — it returns the bundle — so it is deliberately not registered;
`/api/v1/health` is the real one and is covered by `/api/v1`. `/realtime`,
`/v1/realtime` and `/logs/stream` answer only to a websocket upgrade, which is
why a plain GET gets the bundle; they are registered for the upgrade path.
- `hardware.amd-npu.lemonade` (nix-amd-ai `modules/amd-npu.nix`): `port`
  default 13305, `allowedOrigins` emitted as `LEMONADE_ALLOWED_ORIGINS`;
  loopback origins always allowed, an absent `Origin` always allowed.

So the useful lemonade surface behind a proxy is its **origin-root API and
websocket paths**, not its UI.

### Subdomains have no DNS here

MagicDNS resolves `halo` and `<host>.<tailnet>.ts.net` and has no wildcard under
a machine name. Avahi (`nixos/core/networking.nix`) publishes `halo.local` on
the LAN only, never over Tailscale, and also has no subdomains. Per-service
subdomains would need DNS work outside this repo.

### The firewall posture this repo already documents

`nixos/services/tailscale.nix` sets `trustedInterfaces = ["tailscale0"]`, so
**tailnet traffic to port 80 is already accepted with no firewall change**.
`hosts/halo/default.nix` says of lemond: "Safe only because the port stays out
of allowedTCPPorts and tailscale0 is a trusted interface ... so the tailnet
reaches it and the LAN does not", and
`docs/superpowers/specs/2026-09-01-halo-llm-inference-design.md` repeats it.
`nixos/services/jellyfin.nix` is the counter-pattern in this same directory:
"Deliberately not services.jellyfin.openFirewall — that opens every interface",
scoping ports through `networking.firewall.interfaces.<iface>`.

## Decisions

1. **One proxy per host, enabled on `halo` only.** houston is loopback-only by
   design, so a single tailnet-wide proxy would force it to listen off-loopback
   — the opposite of what it is built for. (lemond on halo already binds
   `0.0.0.0` deliberately; houston is the constraint here, not lemond.) `halo` is
   the always-on box that runs both registrants and never leaves the house.
   g6's server role is explicitly temporary and it roams. Enabling it elsewhere
   later is one attribute.

2. **Path prefixes, not subdomains** — subdomains have no DNS. houston claims
   the root; lemonade claims its origin-root API and websocket paths. Nothing
   is prefix-stripped, so no registrant needs a base-path setting it does not
   have. This is another host's reverse proxy's shape generalised: a service declares the paths it
   owns and the module writes the `reverse_proxy` lines.

3. **lemonade's UI is deliberately not proxied.** Two reasons: it redirects
   every phone browser to an app store, so it cannot serve the stated goal; and
   hosting an LLM chat UI that renders model output same-origin with houston
   would put houston's `Path=/` control cookie inside that page's reach.
   `http://halo:13305` keeps serving the UI to desktop browsers unchanged.
   Designed twice: the vhost already answers to two distinct names (`halo` and
   `<host>.<tailnet>.ts.net`), which are distinct browser origins, so lemonade's
   UI could take the root of the second name and dodge the cookie exposure
   entirely. Rejected anyway — the app-store redirect kills the phone case
   whichever name serves it, and making *which name you type* decide *which
   service you get* is a worse memory trap than the port it replaces.

4. **`LEMONADE_ALLOWED_ORIGINS` does not need a change.** The proxy serves no
   lemonade *page*, so no new browser origin ever calls `lemond`: API clients
   send no `Origin` and are always allowed, and the only page on
   `http://halo` is houston, which never calls `/api/v1`. Adding origins that
   nothing sends would widen CORS for no reason. If a browser UI is ever served
   from `http://halo`, adding its origin is a one-line change.

5. **No dashboard page.** houston *is* the dashboard and it occupies the root.

6. **Host header preserved** (Caddy's default). The vhost is addressed only by
   names houston's gate accepts: `halo`, `<host>.<tailnet>.ts.net`, the tailnet
   IP, `localhost`. `halo.local` is deliberately **not** served — houston would
   421 on it, since a `.local` name never enters its gate.

7. **The firewall opens port 80 and nothing else, on named LAN interfaces
   only, and halo names none.** Reaching the proxy over Tailscale needs no
   firewall change at all, because `tailscale0` is already trusted. A blanket
   `allowedTCPPorts = [80]` would instead expose lemond's unauthenticated API
   and houston's tmux control to the TV's network segment, reversing the
   posture halo's own config documents twice. The module therefore takes a
   `lanInterfaces` list (the `jellyfin.nix` pattern) that opens **only** TCP 80
   on the interfaces named; halo leaves it empty. **This is a deliberate
   deviation from the task's acceptance criterion 4 read literally** — port 80
   is the only port this module can ever open, but on halo it opens none — and
   it must be stated in the PR body.

## Requirements

- **R1** New NixOS module `nixos/services/local-proxy.nix`, imported from
  `nixos/services/default.nix`, off by default.
- **R2** Top-level options are `enable`, `hostNames` (list of names the vhost
  answers to, default `[config.hostname "localhost"]`), `lanInterfaces` and
  `services`. `services.<name>` is a submodule: `upstream` (default
  `127.0.0.1`), `port`, `paths`, `streaming`, `responseHeaderTimeout`.
  Registering a service is one attribute set; no `extraConfig` string editing.
- **R3** The module assembles the Caddyfile body as one `handle` block per
  declared path (`handle` with no matcher for the `/` catch-all), using prefix
  globs (`/api/v1*`, not `/api/v1/*`) per the other host's lesson. `handle` is used
  rather than bare `reverse_proxy` matchers because Caddy sorts `handle` blocks
  by matcher specificity and evaluates the matcher-less one last, so the root
  service cannot swallow another service's paths.
- **R4** `streaming = true` emits `flush_interval -1`.
  `responseHeaderTimeout` is a `nullOr str` defaulting to `null` (Caddy's own
  default is no limit); both registrants set **`300s`**, the value another host's reverse proxy's
  prior art uses.
- **R5** Assertions: at most one service claims `/`; no path is claimed twice.
- **R6** Plain HTTP only (`http://` site addresses, so automatic HTTPS stays
  off). `lanInterfaces` (default `[]`) opens TCP 80, and nothing else, on the
  named interfaces via `networking.firewall.interfaces`. Its option description
  must spell out what naming an interface exposes — every registrant behind the
  proxy, unauthenticated, to that network segment — not merely that it opens a
  port.
- **R7** halo enables the module with
  `hostNames = [config.hostname "<host>.<tailnet>.ts.net" "<host-ip>" "localhost"]`
  and registers:
  - `houston` — port 9090, `paths = ["/"]`, `streaming = true`,
    `responseHeaderTimeout = "300s"`;
  - `lemonade` — port from `config.hardware.amd-npu.lemonade.port`,
    `paths = ["/api/v1" "/api/v0" "/v1" "/v0" "/realtime" "/logs/stream"]`
    (the four probed API roots plus the two websocket endpoints;
    `/v1/realtime` is already covered by `/v1`), `streaming = true`,
    `responseHeaderTimeout = "300s"`.
- **R8** The PR body states the host choice, the prefix-vs-subdomain decision
  and why, the `LEMONADE_ALLOWED_ORIGINS` answer, and the firewall deviation
  (task AC5).
- **R9** Verification, without `switch`:
  `git add` the new file first (untracked files are invisible to the flake),
  then `nix build .#nixosConfigurations.halo.config.services.caddy.configFile`
  (this runs `caddy fmt` at build time), `caddy validate --adapter caddyfile`
  on the result, and
  `nix build .#nixosConfigurations.halo.config.system.build.toplevel --dry-run`.

## Non-requirements

- No dashboard/index HTML; no HTTPS or ACME.
- No prefix **stripping** (`handle_path`): neither registrant needs it, and
  adding an untested code path for a hypothetical future service is the
  speculative robustness `CLAUDE.md` rules out.
- No change to houston's Caddy routing; houston itself is now Nix-managed (see home/ai/houston).
- Not enabled on g5, g6, mbp or installer.

## Accepted risks and known limitations (to be stated in the PR body)

- **Shared origin.** houston's `houston_token` cookie is `Path=/` on
  `http://halo`, so a browser that manually opens `http://halo/api/v1/...`
  sends it to `lemond`, where it may land in a log. Both services run as the
  same user on the same box, so the blast radius is a log file that user
  already owns. Not mitigated in code, because header stripping would silently
  break any future registrant that legitimately uses cookies. Decision 3 keeps
  the far worse version of this — an LLM UI same-origin with houston — off the
  table.
- **Unregistered paths fall through to houston, which answers 200.** houston
  mounts `/` as an SPA handler, so a path no service claims returns
  `index.html` with a 200 rather than a 404. A lemonade client that used a root
  outside the four probed ones would parse HTML as JSON and see a bogus
  success, not a clean failure. The registered set covers lemond's whole
  non-bundle surface as probed above, and adding a root later is one list
  entry — but the failure mode, if one is ever missed, is silent.
- **lemonade websocket fallback.** If `/v1/realtime` fails, the client reads
  `/health` and reconnects to a server-reported `websocket_port` on a different
  port. That fallback bypasses the proxy and reaches a port nothing opens.
  Realtime over the proxy is therefore best-effort.
- **MagicDNS name is not guaranteed.** houston learns
  `<host>.<tailnet>.ts.net` from a reverse lookup at startup with a 2s timeout;
  if that times out, requests to that name get a 421 until houston is restarted
  (its own `-hostname` flag is the documented cure). Bare `halo` is unaffected.
- **houston must be restarted on loopback.** It is running today bound to
  `<host-ip>:9090`, not loopback, so the root will 502 until it is started
  on its default `-addr`. That restart is the human's, after the rebuild, and
  it is the point of the issue: houston goes back to loopback-only.
