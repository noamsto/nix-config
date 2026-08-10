# Phase 0 — Metered Cost Baseline for the Claude Subscription Decision

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a defensible metered-API cost for the last month of Claude Code usage on `mbp-m4-pro`, post it as a verdict on issue #151, and land a launchd agent that archives `~/.claude/projects/` so a longer window exists next time.

**Architecture:** Two independent deliverables. (A) Analysis — a throwaway `jq`+`awk` reference computation in the scratchpad, cross-checked against `ccusage`, with the cache-write/cache-read multipliers as the thing being validated; no analysis code lands in the repo. (B) Config — one new Home Manager module, `home/ai/claude-code/session-archive.nix`, that mirrors the live session tree (never deletes) and compresses only what Claude Code has already pruned upstream.

**Tech Stack:** `ccusage` 20.0.17 (`nix run nixpkgs#ccusage`, not installed on this host), `jq`, `awk`, `pkgs.writeShellApplication` (build-time shellcheck), Home Manager `launchd.agents` (darwin), `rsync`, `zstd`, `gh`.

---

## Facts already established on this machine

Measured 2026-08-10 in this worktree. Do not re-derive; do re-confirm cheaply in Task 1.

| Fact | Value | Note |
|---|---|---|
| Project dirs | 168 | vs 269 on the work machine |
| `*.jsonl` session files | 1376 | **includes nested `*/subagents/agent-*.jsonl`** |
| Corpus size | 1.6 GB | uncompressed JSONL |
| Oldest file mtime | 2026-07-11 | ≈30-day window, matches the issue's "history is short" |
| `ccusage` on PATH | **absent** | must be `nix run nixpkgs#ccusage --` |
| `ccusage` in nixpkgs | 20.0.17 | issue cites 20.0.19; note the delta in the report |

## File structure

| Path | Kind | Responsibility |
|---|---|---|
| `$SCRATCH/fixture/proj/session.jsonl` | create (scratch) | Hand-built session with known token counts — the red test for the cost math |
| `$SCRATCH/cost-baseline.sh` | create (scratch) | Reference metered-cost computation; single source of truth for the number |
| `$SCRATCH/test-archive.sh` | create (scratch) | Red/green test for the archive script, run against a throwaway `$HOME` |
| `$SCRATCH/issue-comment.md` | create (scratch) | Body posted to issue #151 |
| `home/ai/claude-code/session-archive.nix` | **create (repo)** | `claude-session-archive` package + daily launchd agent |
| `home/ai/claude-code/default.nix:182-187` | **modify (repo)** | Add `./session-archive.nix` to `imports` |

`$SCRATCH` = `/private/tmp/claude-501/-Users-noams-Data-git--worktrees-noams-nix-config-feat-151-phase-0-metered-cost-baseline-for-the-cl/d156e084-c9d4-4f77-9133-bf8078519e23/scratchpad`. Nothing under `$SCRATCH` is committed — the session logs are personal data and the analysis is a one-shot.

---

## Task 1: Confirm the corpus and enumerate the models actually used

**Files:** none (measurement only)

- [ ] **Step 1: Re-confirm corpus shape**

```bash
ls ~/.claude/projects | wc -l
find ~/.claude/projects -name '*.jsonl' | wc -l
find ~/.claude/projects -path '*/subagents/*' -name '*.jsonl' | wc -l
du -sh ~/.claude/projects
```

Expected: ~168 dirs, ~1376 files, a non-zero subagent count, ~1.6G. Record all four — they go in the report.

- [ ] **Step 2: Establish the real retention window from message timestamps, not mtimes**

```bash
find ~/.claude/projects -name '*.jsonl' -print0 \
  | xargs -0 cat \
  | jq -r 'select(.timestamp) | .timestamp[0:10]' \
  | sort | uniq -c | sort -k2
```

Expected: a dated histogram starting around 2026-07-11 and ending 2026-08-10. Save it — this is the daily distribution needed in Task 8. Write it to `$SCRATCH/daily-messages.txt`.

- [ ] **Step 3: Enumerate distinct model ids**

```bash
find ~/.claude/projects -name '*.jsonl' -print0 \
  | xargs -0 cat \
  | jq -r 'select(.message.model) | .message.model' \
  | sort | uniq -c | sort -rn
```

Expected: a short list (opus / sonnet / haiku ids). Record it verbatim — Task 2 prices exactly these ids and nothing else.

- [ ] **Step 4: Check whether `cache_creation` is TTL-split**

```bash
find ~/.claude/projects -name '*.jsonl' -print0 \
  | xargs -0 cat \
  | jq -c 'select(.message.usage.cache_creation) | .message.usage.cache_creation' \
  | sort -u | head -5
```

If lines like `{"ephemeral_5m_input_tokens":N,"ephemeral_1h_input_tokens":M}` appear, the two TTLs price differently (5m ≠ 1h multiplier) and Task 3 must split them. If the field is absent everywhere, all cache writes are 5m and the single multiplier is correct. **Record which case holds** — this changes the formula.

---

## Task 2: Pin the price constants from the `claude-api` skill

**Files:** none (constants recorded for Task 3)

- [ ] **Step 1: Load the skill**

Invoke the `claude-api` skill. Do **not** answer from memory — the whole decision is downstream of these numbers.

- [ ] **Step 2: Extract, for every model id from Task 1 Step 3**

Record a table: model id, `P_in` ($/Mtok), `P_out` ($/Mtok), cache-write multiplier (5m, and 1h if Task 1 Step 4 found it), cache-read multiplier, web-search $/1k calls.

- [ ] **Step 3: Confirm the issue's assumed multipliers**

The issue assumes cache write = `1.25 × P_in`, cache read = `0.10 × P_in`. State explicitly whether the skill confirms both. If either differs, use the skill's value and flag the discrepancy in the report.

- [ ] **Step 4: Write the constants down**

Save the table to `$SCRATCH/prices.md`, with a one-line provenance note ("from `claude-api` skill, read 2026-08-10"). The report in Task 9 quotes this verbatim.

---

## Task 3: Build the reference cost computation, test-first

**Files:**
- Create: `$SCRATCH/fixture/proj/session.jsonl`
- Create: `$SCRATCH/cost-baseline.sh`

- [ ] **Step 1: Write the fixture with hand-computable numbers**

```bash
mkdir -p "$SCRATCH/fixture/proj"
cat > "$SCRATCH/fixture/proj/session.jsonl" <<'EOF'
{"timestamp":"2026-08-01T10:00:00Z","requestId":"req_a","message":{"model":"claude-opus-4-20250514","usage":{"input_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
{"timestamp":"2026-08-01T10:00:01Z","requestId":"req_b","message":{"model":"claude-opus-4-20250514","usage":{"input_tokens":0,"cache_creation_input_tokens":1000000,"cache_read_input_tokens":0,"output_tokens":0}}}
{"timestamp":"2026-08-01T10:00:02Z","requestId":"req_c","message":{"model":"claude-opus-4-20250514","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000000,"output_tokens":0}}}
{"timestamp":"2026-08-01T10:00:03Z","requestId":"req_c","message":{"model":"claude-opus-4-20250514","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000000,"output_tokens":0}}}
{"timestamp":"2026-08-01T10:00:04Z","requestId":"req_d","message":{"model":"claude-opus-4-20250514","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1000000}}}
EOF
```

Replace `claude-opus-4-20250514` with a model id that actually appeared in Task 1 Step 3, and use that model's prices below.

**Expected total by hand** (substitute the Task 2 numbers): `P_in + 1.25×P_in + 0.10×P_in + P_out`. `req_c` is deliberately duplicated — a correct script dedupes on `requestId` and counts that cache read **once**. If the script returns `+0.10×P_in` extra, dedup is broken.

- [ ] **Step 2: Write the script**

```bash
cat > "$SCRATCH/cost-baseline.sh" <<'EOF'
#!/usr/bin/env bash
# Reference metered cost from Claude Code session JSONL.
# Usage: cost-baseline.sh <projects-dir> <price-table.tsv>
# Price table columns: model  p_in  p_out  mult_write  mult_read   ($/Mtok, multipliers)
set -euo pipefail

root=$1
prices=$2

find "$root" -name '*.jsonl' -print0 \
  | xargs -0 cat \
  | jq -r '
      select(.message.usage != null and .message.model != null)
      | [ (.requestId // .message.id // "anon"),
          .message.model,
          (.timestamp[0:10]),
          (.message.usage.input_tokens // 0),
          (.message.usage.cache_creation_input_tokens // 0),
          (.message.usage.cache_read_input_tokens // 0),
          (.message.usage.output_tokens // 0),
          (.message.usage.server_tool_use.web_search_requests // 0)
        ] | @tsv' \
  | sort -u -k1,1 \
  | awk -v pricefile="$prices" '
      BEGIN {
        FS = OFS = "\t"
        while ((getline line < pricefile) > 0) {
          split(line, p, "\t")
          if (p[1] == "" || p[1] ~ /^#/) continue
          pin[p[1]] = p[2]; pout[p[1]] = p[3]; mw[p[1]] = p[4]; mr[p[1]] = p[5]
        }
      }
      {
        model = $2; day = $3
        if (!(model in pin)) { unpriced[model]++; next }
        c = ($4 * pin[model] + $5 * mw[model] * pin[model] \
             + $6 * mr[model] * pin[model] + $7 * pout[model]) / 1000000
        by_model[model] += c; by_day[day] += c; total += c
        searches += $8
      }
      END {
        for (m in by_model) printf "model\t%s\t%.2f\n", m, by_model[m]
        for (d in by_day)   printf "day\t%s\t%.2f\n", d, by_day[d]
        printf "websearch_calls\t\t%d\n", searches
        printf "TOTAL\t\t%.2f\n", total
        for (m in unpriced) printf "UNPRICED\t%s\t%d\n", m, unpriced[m]
      }'
EOF
chmod +x "$SCRATCH/cost-baseline.sh"
shellcheck "$SCRATCH/cost-baseline.sh"
```

Expected: `shellcheck` exits 0 with no output. Fix anything it reports before continuing.

- [ ] **Step 3: Write the price table from Task 2**

```bash
printf '%s\t%s\t%s\t%s\t%s\n' 'claude-opus-4-20250514' '<P_in>' '<P_out>' '1.25' '0.10' \
  > "$SCRATCH/prices.tsv"
```

One line per model id from Task 1 Step 3, values from `$SCRATCH/prices.md`. If Task 1 Step 4 found TTL-split cache creation, add columns for the 1h write multiplier and extend the `awk` `c =` expression to read `.message.usage.cache_creation.ephemeral_1h_input_tokens` as a separate field.

- [ ] **Step 4: Run against the fixture — this is the red/green gate**

```bash
"$SCRATCH/cost-baseline.sh" "$SCRATCH/fixture" "$SCRATCH/prices.tsv"
```

Expected: `TOTAL` equals the hand figure from Step 1, and `UNPRICED` does not appear. If `TOTAL` is high by exactly `0.10 × P_in`, the `sort -u -k1,1` dedup is not firing — fix before touching real data.

- [ ] **Step 5: Run against the real corpus**

```bash
time "$SCRATCH/cost-baseline.sh" ~/.claude/projects "$SCRATCH/prices.tsv" \
  | tee "$SCRATCH/reference-cost.txt"
```

Expected: a `TOTAL`, per-model and per-day lines, and **no `UNPRICED` lines**. Any `UNPRICED` model means Task 2 missed an id — go back and price it; silently dropping a model understates the answer.

---

## Task 4: Run `ccusage` and check it against the trap

**Files:** none

- [ ] **Step 1: Get the monthly total, forcing token-based pricing**

```bash
nix run nixpkgs#ccusage -- claude monthly -m calculate -b -j \
  > "$SCRATCH/ccusage-monthly.json"
jq '.' "$SCRATCH/ccusage-monthly.json" | head -60
```

`-m calculate` is load-bearing: under a Max subscription the logged `costUSD` is absent or zero, and the default `auto` mode would report near-nothing. If the JSON shape differs from expectation, read `nix run nixpkgs#ccusage -- claude monthly --help` rather than guessing keys.

- [ ] **Step 2: Confirm it separates cache read from cache write**

```bash
jq -r '.. | objects | keys[]' "$SCRATCH/ccusage-monthly.json" | sort -u | grep -i cache
```

Expected: **two distinct** cache fields (creation/write and read). One combined `cacheTokens` field means the tool cannot express the 1.25 vs 0.10 split — record that, and treat `$SCRATCH/reference-cost.txt` as authoritative.

- [ ] **Step 3: Check whether it walks the `subagents/` subdirectories**

```bash
find ~/.claude/projects -name '*.jsonl' | wc -l
find ~/.claude/projects -maxdepth 2 -name '*.jsonl' | wc -l
```

If the two counts differ (they will — Task 1 found nested subagent logs) and `ccusage`'s total is close to a corpus-minus-subagents computation, `ccusage` is silently undercounting. Test it directly: rerun `$SCRATCH/cost-baseline.sh` over a `find`-filtered tree that excludes `*/subagents/*` and see which of the two totals `ccusage` matches.

- [ ] **Step 4: Compare price sources**

```bash
nix run nixpkgs#ccusage -- claude monthly -m calculate -O -j | jq '.totals // .'
```

`-O` uses `ccusage`'s bundled pricing instead of fetching LiteLLM's. If offline and online totals differ, or either differs from the Task 2 constants, say so — that is the "stale price" failure mode the issue warns about.

---

## Task 5: Cross-check on one project and reconcile

**Files:** none

- [ ] **Step 1: Pick the busiest single project**

```bash
du -sh ~/.claude/projects/* | sort -h | tail -3
```

- [ ] **Step 2: Compute that project both ways**

```bash
proj=~/.claude/projects/<busiest-dir>
"$SCRATCH/cost-baseline.sh" "$proj" "$SCRATCH/prices.tsv" | grep TOTAL
nix run nixpkgs#ccusage -- claude daily -m calculate -i -j \
  | jq --arg p '<busiest-dir>' '[.daily[]? | .projects[]? | select(.project==$p) | .totalCost] | add'
```

Expected: within a few percent. Adjust the `jq` path to the actual `-i` output shape — inspect it first with `| jq 'keys'`.

- [ ] **Step 3: If they disagree by more than ~10%, investigate before proceeding**

Likely causes, in order of probability: subagent files (Task 4 Step 3), dedup key mismatch (`requestId` vs `message.id`), synthetic/`<synthetic>` model entries, or a model priced differently in LiteLLM. Do not average the two numbers or pick the nicer one.

- [ ] **Step 4: Declare the authoritative number and why**

Write one paragraph into `$SCRATCH/reconciliation.md`: which computation is authoritative, what the other said, and what explains the gap. This paragraph goes in the report — the issue asks explicitly not to trust a tool for being popular.

---

## Task 6: Per-project and per-model split

**Files:** none

- [ ] **Step 1: Per-model, from the authoritative computation**

```bash
grep '^model' "$SCRATCH/reference-cost.txt" | sort -t"$(printf '\t')" -k3 -rn
```

- [ ] **Step 2: Per-project**

```bash
for d in ~/.claude/projects/*/; do
  printf '%s\t%s\n' "$(basename "$d")" \
    "$("$SCRATCH/cost-baseline.sh" "$d" "$SCRATCH/prices.tsv" | awk -F'\t' '$1=="TOTAL"{print $3}')"
done | sort -k2 -rn | tee "$SCRATCH/by-project.txt" | head -15
```

Expected: a ranked list. Note the top 5 and what share of total they carry.

- [ ] **Step 3: Price the server-tool calls, which the token total excludes**

```bash
awk -F'\t' '$1=="websearch_calls"{print $3}' "$SCRATCH/reference-cost.txt"
```

Multiply that call count by the web-search $/1k-calls figure from `$SCRATCH/prices.md` and add it to the headline as a separate line item. `cost-baseline.sh` deliberately reports the count rather than folding it into `TOTAL` — server tools are billed per call, and keeping them separate makes it visible whether they matter at all. If the count is negligible, say so and move on.

---

## Task 7: Daily distribution and stall detection

**Files:** none

- [ ] **Step 1: Daily spend, sorted by date and by size**

```bash
grep '^day' "$SCRATCH/reference-cost.txt" | sort -k2 | tee "$SCRATCH/by-day.txt"
grep '^day' "$SCRATCH/reference-cost.txt" | sort -t"$(printf '\t')" -k3 -rn | head -10
```

- [ ] **Step 2: Compute the concentration**

```bash
awk -F'\t' '{s+=$3; v[NR]=$3} END {n=asort(v); t=0; for(i=n;i>n-5;i--) t+=v[i];
  printf "total %.2f  top5days %.2f  share %.0f%%  mean/day %.2f\n", s, t, 100*t/s, s/n}' \
  "$SCRATCH/by-day.txt"
```

If `awk` lacks `asort` (BSD awk on macOS does), use `sort -rn` piped into a small `awk` accumulator instead. The number that matters: **what share of the month the top 5 days carry.** The issue calls this out — a spiky profile and a flat profile of equal total imply different plans.

- [ ] **Step 3: Look for rate-limit stalls on heavy days**

```bash
find ~/.claude/projects -name '*.jsonl' -print0 | xargs -0 cat \
  | jq -r 'select(.timestamp) | .timestamp' | sort \
  | awk -F'[T:Z]' '{t=$2*3600+$3*60+$4; d=$1;
      if (d==pd && t-pt > 900) printf "%s gap %.0f min\n", d, (t-pt)/60;
      pd=d; pt=t}' \
  | sort | uniq -c | sort -rn | head -20
```

Expected: a list of days with >15-minute intra-session gaps. Cross-reference against the top-5 heavy days from Step 2. **Be honest about the ambiguity** — a gap is equally consistent with the human going to lunch. Report it as a weak signal or not at all; do not present it as proven rate-limiting.

---

## Task 8: Write and post the issue comment

**Files:**
- Create: `$SCRATCH/issue-comment.md`

- [ ] **Step 1: Draft the comment**

Required sections, in order:

1. **Corpus & window** — the four numbers from Task 1, the actual date range, and the caveat that ~30 days cannot show seasonality.
2. **Prices used** — the table from `$SCRATCH/prices.md` with its provenance line, and whether the 1.25 / 0.10 multipliers were confirmed.
3. **Method** — which computation is authoritative and why (`$SCRATCH/reconciliation.md`), including the `ccusage` version delta (nixpkgs 20.0.17 vs the issue's 20.0.19) and whether `ccusage` counted subagent logs.
4. **Metered $/month** — headline number, per-model split, top projects with their share.
5. **Daily distribution** — the by-day series, the top-5-day share, mean vs median.
6. **Stalls** — the Task 7 Step 3 finding, hedged appropriately, or "no usable signal".
7. **Verdict** — against the exit criterion: comfortably under $100 → drop the subscription and skip Phases 1–3; comfortably over → keep it and close #151; **ambiguous → say so and name what would resolve it** (most likely: re-run after the archive from Task 9 has accumulated 60–90 days).

No raw prompts, file contents, or project paths that leak client/repo names beyond what is already public in this repo's issues. Aggregate numbers only.

- [ ] **Step 2: Post it**

```bash
gh issue comment 151 --body-file "$SCRATCH/issue-comment.md"
```

Expected: prints the comment URL.

---

## Task 9: Archive module — write the test first

**Files:**
- Create: `$SCRATCH/test-archive.sh`

- [ ] **Step 1: Write the test**

```bash
cat > "$SCRATCH/test-archive.sh" <<'EOF'
#!/usr/bin/env bash
# Red/green test for claude-session-archive, run against a throwaway $HOME.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/projects/demo/sess/subagents"
printf '{"a":1}\n' > "$tmp/.claude/projects/demo/live.jsonl"
printf '{"b":2}\n' > "$tmp/.claude/projects/demo/sess/subagents/agent-x.jsonl"

HOME="$tmp" claude-session-archive

mirror="$tmp/.local/state/claude-session-archive/projects"
test -f "$mirror/demo/live.jsonl"                     || { echo "FAIL: live file not mirrored"; exit 1; }
test -f "$mirror/demo/sess/subagents/agent-x.jsonl"   || { echo "FAIL: subagent log not mirrored"; exit 1; }

# Claude Code prunes the session upstream; the archive must keep it, compressed.
rm "$tmp/.claude/projects/demo/live.jsonl"
HOME="$tmp" claude-session-archive

test -f "$mirror/demo/live.jsonl.zst"                 || { echo "FAIL: pruned file not compressed"; exit 1; }
test ! -f "$mirror/demo/live.jsonl"                   || { echo "FAIL: uncompressed copy left behind"; exit 1; }
test -f "$mirror/demo/sess/subagents/agent-x.jsonl"   || { echo "FAIL: still-live file was compressed"; exit 1; }

echo PASS
EOF
chmod +x "$SCRATCH/test-archive.sh"
shellcheck "$SCRATCH/test-archive.sh"
```

Expected: `shellcheck` exits silently.

- [ ] **Step 2: Run it to confirm it fails**

```bash
"$SCRATCH/test-archive.sh"
```

Expected: FAIL — `claude-session-archive: command not found`.

---

## Task 10: Archive module — implement

**Files:**
- Create: `home/ai/claude-code/session-archive.nix`
- Modify: `home/ai/claude-code/default.nix:182-187` (the `imports` list)

- [ ] **Step 1: Write the module**

```nix
{
  pkgs,
  lib,
  config,
  ...
}: let
  # Both paths derive from $HOME inside the script, not from Nix, so the whole
  # job can be exercised against a throwaway HOME.
  claude-session-archive = pkgs.writeShellApplication {
    name = "claude-session-archive";
    runtimeInputs = [pkgs.rsync pkgs.zstd pkgs.findutils];
    text = ''
      src="$HOME/.claude/projects"
      dst="$HOME/.local/state/claude-session-archive/projects"

      [ -d "$src" ] || exit 0
      mkdir -p "$dst"

      # No --delete: Claude Code prunes its own tree at ~30 days, the archive
      # never does. Sessions are append-only, so -a picks up in-place growth.
      rsync -a "$src/" "$dst/"

      # Compress only what upstream has already dropped. Compressing a file
      # that still exists in $src would just be re-inflated by the next rsync.
      cd "$dst"
      find . -name '*.jsonl' -type f -print0 | while IFS= read -r -d "" f; do
        [ -e "$src/$f" ] || zstd -q --rm -- "$f"
      done
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    home.packages = [claude-session-archive];

    # Daily, in the "user" domain — no Aqua session needed. launchd coalesces
    # runs missed while the laptop was asleep to the next wake, unlike cron.
    launchd.agents.claude-session-archive = {
      enable = true;
      domain = "user";
      config = {
        ProgramArguments = ["${claude-session-archive}/bin/claude-session-archive"];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 15;
          }
        ];
        StandardOutPath = "${config.home.homeDirectory}/.local/state/claude-session-archive.log";
        StandardErrorPath = "${config.home.homeDirectory}/.local/state/claude-session-archive.log";
      };
    };
  }
```

The log path sits in `~/.local/state` (which already exists) rather than inside the archive dir, so launchd never has to create the parent itself.

- [ ] **Step 2: Add it to the imports**

In `home/ai/claude-code/default.nix`, change:

```nix
  imports = [
    ./mcp-profiles.nix
```

to:

```nix
  imports = [
    ./mcp-profiles.nix
    ./session-archive.nix
```

- [ ] **Step 3: Make the new file visible to the flake, then rebuild**

Invoke the `nix-rebuild` skill first. Then:

```bash
git add home/ai/claude-code/session-archive.nix home/ai/claude-code/default.nix
nh darwin switch
```

`git add` is mandatory — an untracked file does not exist as far as the flake is concerned. `nh darwin switch`, not `nh home switch` (see `CLAUDE.local.md`). `writeShellApplication` runs `shellcheck` at build time, so a shellcheck failure surfaces here as a build error.

Expected: build succeeds and activation reports the new launchd agent.

- [ ] **Step 4: Run the test to verify it passes**

```bash
"$SCRATCH/test-archive.sh"
```

Expected: `PASS`.

- [ ] **Step 5: Verify the agent is actually loaded, and prime the archive**

```bash
launchctl list | grep claude-session-archive
time claude-session-archive
du -sh ~/.local/state/claude-session-archive/projects
```

Expected: the agent appears in `launchctl list`; the first (1.6 GB) run takes a minute or two; the mirror size roughly matches `~/.claude/projects`. Record the timing — it goes in the PR body.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(claude-code): archive session logs daily on darwin"
```

The first commit is **expected to fail** — `alejandra` reformats `.nix` files and the hook exits non-zero. `git add` the reformatted files and re-run the **same** command; it passes on the second attempt.

---

## Task 11: Open the PR

**Files:** none

- [ ] **Step 1: Push and open**

```bash
git push -u origin feat/151-phase-0-metered-cost-baseline-for-the-cl
gh pr create --assignee @me \
  --title "feat(claude-code): archive session logs daily on darwin" \
  --body "..."
```

PR body should state: why now (retention is ~30 days, so a longer window is a now-or-never data-collection decision independent of the cost verdict), the mirror-never-deletes / compress-only-orphans design and why compressing live files would be undone by the next rsync, the measured first-run time and size from Task 10 Step 5, and a link to the Task 8 issue comment. Do not write `Closes #151` — issue #151 spans four phases and stays open unless the Task 8 verdict says "keep the subscription".

- [ ] **Step 2: Confirm**

```bash
gh pr view --json url,title,assignees
```

---

## Off-ramp: skipping deliverable B

If Task 1 shows retention is effectively unlimited (oldest session materially older than ~35 days, or evidence that Claude Code never prunes), **skip Tasks 9–11** and instead post the evidence — the oldest-timestamp figure and the pruning behaviour you observed — as part of the Task 8 comment, explicitly stating that the archiving job was not built and why. Do not build something useless to have a PR to show.

## Out of scope

Phases 1–4 of issue #151: the quality suite, the candidate slate, the dispatcher bake-off, the pre-registered decision rule, and ungating `programs.dispatcher.profile` on personal. None of it starts until the Task 8 verdict lands.
