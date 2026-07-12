# Dispatcher engine autonomy, outcome logging, and cross-model review

**Status:** design — awaiting review
**Date:** 2026-07-12
**Repo:** nix-config (personal / GitHub)
**Artifacts touched:** `home/ai/claude-code/DISPATCHER_PROTOCOL.md`, `home/ai/claude-code/dispatch-orchestration.md`, `home/ai/claude-code/commands/dispatcher.md`, `home/ai/claude-code/WORKER_PROTOCOL.md`, `home/ai/claude-code/crew.sh`, `home/terminal/fish/default.nix`, nix plugin + MCP provisioning.

## Problem

The dispatcher harness treats the worker **engine** as a manual opt-in flag (`dispatch … --agent codex`), so codex never runs unless the human remembers to type it — in practice, never. The dispatcher should judge the engine autonomously, the same way it already judges tier and model. Three follow-on gaps surface once engine is a real lever:

1. There is **no data** on which engine/model wins for which task shape (verified: the repo has zero benchmarks, latency, or outcome records — routing is qualitative heuristic, and the fan-out cap comment even admits "the old fixed ≤4 was an unmeasured guess"). Autonomous routing should start capturing lightweight signal so the heuristic can improve.
2. The review gate reviews **same-family** (a claude worker reviews with claude subagents; a codex worker with codex), so the second engine's different blind spots never get exercised where they pay off most — review.
3. The codex model is **hard-pinned to `gpt-5.5`** in prose, which rots every time OpenAI ships a new model; the dispatcher should choose across gpt models the way it chooses across claude models.

## Decisions (locked with the user)

1. **Engine is a co-equal judged lever, no default.** Every task → `{tier, engine, model}`. claude ⇄ codex weighed equally by task fit, not a manual flag.
2. **Outcome logging rides the existing crew bus** (single `events.jsonl`); no new coordination system. Explicitly **not** MCP or A2A — the local, single-machine, token-free file bus is the correct layer.
3. **No single gpt pin** — a maintained model map holds two model ladders (claude + codex), tier→model; prose references the map, never a version string.
4. **Deep-tier cross-model review** — a deep worker's review gate must include an engine different from the implementer, findings reconciled. standard/trivial review unchanged.
5. **Fable is in, as a gated `deep`-only escalation above opus** — not a peer of opus.

## Non-goals

- Cross-model review for standard/trivial tiers.
- Cross-model `/design` or `/audit` (only review).
- Any auto-selection driven by the logged data — the human reviews the data; the rubric stays a human-tuned heuristic.
- Cross-repo rollup of the outcome log (the bus is per-repo; a global sink is a later, separate change).
- Capturing codex's async GitHub-App review findings into the log (they live on the PR, not the bus).

---

## Design

### 1. Routing model — three orthogonal levers

The dispatcher judges every task into **`{tier, engine, model}`**:

| Lever | Controls | Values |
|---|---|---|
| **Tier** | pipeline depth (critics) | `trivial` (no critics) · `standard` (+plan-critic) · `deep` (+spec & plan critics) |
| **Engine** | who implements | **claude** ⇄ **codex** — weighed equally, per task, no default |
| **Model** | implementer strength, scaled by tier *within* the chosen engine | see the model map (§2) |

Engine is chosen by task fit as an **active judgment**:
- claude leans: UI/frontend, nuanced reasoning, ambiguity.
- codex leans: large mechanical refactors, wide-but-shallow sweeps, deliberate second-engine perspective.
- Neutral fit → the dispatcher is free to pick either and states why.

**Profile constraint (unavoidable):** codex is **work-profile only** — not installed on personal hosts (g6, mbp), and `dispatch` hard-aborts `--agent codex` there. So "co-equal engines" holds only on the **work profile** (g5). On personal profiles the dispatcher is claude-only. This is documented in the protocol, not worked around.

### 2. Model map — the single source of truth

One table in `dispatch-orchestration.md` is authoritative for both ladders. Rubric prose says "the tier-appropriate model from the model map for the chosen engine" and never names a version, so it does not rot.

| Tier | claude ladder | codex ladder |
|---|---|---|
| `deep` | **opus** *(→ escalate to Fable, §5)* | current top gpt (seed: `gpt-5.6`) |
| `standard` | **sonnet** | current mid gpt (seed: `gpt-5.5`) |
| `trivial` | **sonnet** (or **haiku** if truly trivial) | current light gpt |

Concrete model names live **only in this table**. When OpenAI (or Anthropic) ships a new model, bump this one table; nothing else references a version. `dispatch` does not validate the model slot (verified — it passes `-m $model`/`--model $model` straight through), so the map is advisory to the dispatcher's judgment, enforced by nothing but the rubric.

Codex reasoning effort continues to scale with tier automatically (deep→high, standard→medium, trivial→low), independent of which gpt model is chosen.

### 3. Outcome logging — on the crew bus

**Why the bus, not MCP/A2A:** coordination is single-machine, single-repo, and must stay token-free. `crew watch`/`await` are held bash calls (zero tokens); an MCP/A2A layer would route coordination through the model's context (tokens) and add a daemon/port/auth failure surface. The bus is already a durable, per-repo, append-only `events.jsonl` keyed by `crew_id` that accumulates across runs. It is the right layer; MCP and A2A are explicitly rejected.

The outcome signal is already ~90% present — workers emit `pr_open`/`done`/`failed` status events with timestamps. Two additions complete the picture:

1. **`dispatch` stamps the decision.** On scaffold, append one `kind:"dispatch"` event to `events.jsonl`:
   ```json
   {"ts": <ms>, "crew_id": "<id>", "kind": "dispatch",
    "branch": "<branch>", "engine": "claude|codex", "model": "<model>",
    "tier": "trivial|standard|deep", "shape": "<one-word task-shape tag>"}
   ```
   This is a one-line append via the same mechanism `crew status` uses (jq-built line `>> events.jsonl`). `dispatch` knows all these fields at scaffold time; `shape` is the dispatcher's own one-word fit tag (e.g. `mechanical`, `ui`, `ambiguous`) passed through an env var the same way `DISPATCH_SPEC` is.
2. **New `crew report` subcommand.** A jq join of `kind:"dispatch"` events ↔ terminal `kind:"status"` events by `branch`, printing a table: `engine · model · tier · shape · outcome · duration_s · xreview`. Derived fields:
   - `outcome` — from the last terminal status (`pr_open`→merged path / `done` / `failed`).
   - `duration_s` = `terminal_ts − first working_ts` for that branch.
   - `gate_passed` — implied by reaching `pr_open`.
   - `xreview` — see §4; whether the cross-model reviewer surfaced a finding the same-model pass did not (deep only; blank otherwise).

No new store, no schema migration — `crew log` already dumps the same file.

### 4. Deep-tier cross-model review (engine-diverse)

For **deep tier only**, the code-review gate MUST include a reviewer engine **different from the implementer**, with findings reconciled (both / other-only / self-only) so the disagreement surface is the product. standard/trivial review is unchanged.

- **claude implements → codex reviews:** the worker runs the `pr-reviewers` plugin's `/codex-review`, which drives codex through the read-only `codex` MCP server and reconciles against the same-model findings. Clean — the claude worker can run Claude Code slash commands natively.
- **codex implements → claude reviews (the hard direction):** a codex worker runs in the codex CLI and cannot run Claude Code slash commands, so it must invoke a claude reviewer out-of-process (`claude -p '/review …'` or a brokered claude subagent). ⚠️ **Risk:** the known `claude -p` teammate failure (`[[reference_claude_teammate_print_failure]]` — named/background teammates die on `--print` under `teammateMode: auto` + the Nix claude wrapper) may bite here. **The plan phase must validate this path end-to-end (or broker the review another way) before this direction is relied on.**
- The `xreview` column in `crew report` records whether the diverse reviewer caught something the same-model pass missed — this is the data that tells you whether the cross-model pass earns its cost.

**Provisioning (nix, work-profile-gated):**
- Install the `pr-reviewers` plugin (work profile only — codex is work-only). Gate it in the `--settings` overlay `enabledPlugins` alongside the other profile-locked plugins, per the settings-architecture rules.
- Register the read-only `codex` MCP server (`codex mcp-server -c sandbox_mode="read-only" -c approval_policy="never" -c model_reasoning_effort="high"`) via `mcp-servers.nix` so claude workers can reach it.
- Skip Cursor — 2-way review (implementer + one diverse reviewer) only; `cursor-agent` is not installed and is out of scope.

### 5. Fable as a deep-only escalation

Fable (`claude-fable-5`) is the top rung of the **claude** ladder, gated to `deep`, and framed as an **escalation above opus** — not a peer:

> deep tier: default **opus**. Escalate to **Fable** only for a genuinely hard, well-specified, long-horizon task where opus is demonstrably not enough. Fable is ~2× opus cost, its safety classifiers can false-positive on security-adjacent code (a mid-run refusal stalls an unattended worker), and it runs minutes-long turns — treat it as the most expensive lever, used rarely.

**Pre-req to verify before wiring in:** confirm the `claude` CLI / subscription actually serves Fable (`claude --model claude-fable-5 -p "hi"`). `dispatch` passes the model through unvalidated, so an account without Fable access fails at runtime, unattended.

This keeps engines co-equal (claude ⇄ codex) while making Fable a within-claude *intensity* choice — the mirror of codex's gpt ladder.

---

## Files touched

| File | Change |
|---|---|
| `DISPATCHER_PROTOCOL.md` | Rewrite the engine framing: co-equal judged lever (no default); model-map reference; profile constraint; Fable escalation note. |
| `dispatch-orchestration.md` | Add the model-map table (both ladders + Fable rung); update the choosing diagram so engine is a first-class judged branch. |
| `commands/dispatcher.md` | One-line update so the in-session rubric matches the baked protocol. |
| `WORKER_PROTOCOL.md` | Deep-tier cross-model review requirement (engine-diverse, reconciled) + the codex→claude direction caveat. |
| `crew.sh` | Add `crew report` (jq join dispatch↔status by branch) + usage string. |
| `home/terminal/fish/default.nix` | `dispatch` appends the `kind:"dispatch"` event; accept a `shape` tag (env var, like `DISPATCH_SPEC`). |
| nix (settings overlay + `mcp-servers.nix`) | Work-profile-gated `pr-reviewers` plugin + read-only `codex` MCP server. |

## Open risks to resolve in the plan

1. **codex-worker → claude-review path** — validate against the `claude -p` teammate failure, or broker it. Blocks the codex-implements half of §4.
2. **Fable CLI access** — verify before adding the rung; otherwise it's a runtime landmine.
3. **`shape` tag vocabulary** — settle a small closed set (e.g. `mechanical`/`ui`/`ambiguous`/`security`/`wide`) so the log is groupable, not free-text noise.
4. **`crew report` merged-vs-open outcome** — `pr_open` is on the bus but "merged" is not; decide whether `report` shells `gh pr view` for merge state or stops at `pr_open`.
