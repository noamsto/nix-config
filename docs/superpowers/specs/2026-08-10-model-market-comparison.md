# Phase 2 — Pricing the 2026 candidate slate against the measured workload

**Issue:** [#151](https://github.com/noamsto/nix-config/issues/151) · **Written:** 2026-08-10 · **All prices fetched 2026-08-10**

---

## Read this before any number below

Every figure here is a **same-workload repricing with efficiency held equal**. It answers exactly one question:

> If the *identical* token profile — same input, same output, same 10.0 billion cache reads — had been billed by a different provider at their August 2026 prices, what would the invoice have said?

That is a **lower bound, not a forecast.** Issue #151 already names the reason: *"a cheaper model that needs 3× the turns is not cheaper."* The right unit is **$/merge-ready task**, not $/token, and this analysis silently assumes every model is equally efficient. That assumption is **unmeasured and probably false**, and it cuts both ways:

- A weaker model may need more turns, more rework, and more context re-reads — inflating real cost **above** these figures, potentially by multiples.
- A model with a different context window or caching behaviour may **reshape the token profile entirely** rather than reproducing it. A 256K-context model cannot even hold the sessions that produced this profile; it would do different work, not the same work more cheaply.

**Do not present any number here as a predicted bill.** Phase 1 (the quality suite) is what closes this gap. Until it runs, these are floors under a cost that is unknown from above.

Two narrower caveats:

- This workload wrote **151M tokens with a 1-hour TTL** versus 123M at 5 minutes. Several non-Anthropic providers have **no 1-hour tier** — their caches are 5-minute or best-effort — so reproducing this profile on them would force more cache re-writes than measured, pushing their true cost **up**. This does **not** apply uniformly: DeepSeek's disk cache reportedly persists *"a few hours to a few days"* after last use, i.e. longer than Anthropic's 1-hour maximum, so the DeepSeek rows are not optimistic on this axis. Alibaba Qwen's explicit cache is 5-minute.
- Caching is priced here **as if it works**. For most routes that is unverified — see the "if caching fails" column, which is not a footnote but a second price.

---

## The single fact the analysis is built around

Measured window **2026-07-11 → 2026-08-10** (30 days; Phase 0's `meter.json`):

| Field | Tokens | Share of volume |
| --- | ---: | ---: |
| Input (uncached) | 2,478,671 | 0.02% |
| Output | 36,800,629 | 0.36% |
| Cache write (5m) | 122,981,056 | 1.19% |
| Cache write (1h) | 151,305,368 | 1.47% |
| **Cache read** | **10,011,008,388** | **96.96%** |
| Web searches | 0 | — |
| Unique messages | 57,226 | — |

**Cache reads are 97% of all token volume, and $3,787 of the $6,127 Claude bill — 62%.**

> **Correction to the framing in the Phase 2 brief.** The brief states cache reads are "$5,005 of the $6,167 total (81%)". That multiplies all 10.0B reads by **Opus's** $0.50/MTok, then divides by the **actual mixed-model** bill — a hypothetical numerator over a real denominator. Priced per model at the rate each one actually charged, cache reads are **$3,787 (61.8%)** at today's prices and **$4,192 (61.4%)** from September. $5,005 is the correct figure only for the all-Opus hypothetical, which is not what ran.
>
> The correction does not weaken the thesis, it just right-sizes it: **cache reads are still the largest single line by a wide margin, and still the thing that decides a provider's total.** They are 62% of the bill, not 81%.

**A provider's cache-read price, and whether it has prompt caching at all, dominates its total far more than its headline input/output prices.** The rest of this document is mostly consequences of that one sentence.

---

## Method

A repricing engine (`reprice.py`, kept in scratch — analysis is a one-shot, session logs are personal data) applies each provider's prices to the frozen token profile above. Three billing modes:

| Mode | How it bills | Applies to |
| --- | --- | --- |
| `explicit` | Cache writes carry a premium (Anthropic: 1.25× at 5m, 2.0× at 1h); reads at the cheap rate. Requires `cache_control` breakpoints from the client. | Anthropic. Alibaba Qwen offers it, but the Qwen routes priced below expose no caching at all. |
| `implicit` | Automatic. **No write premium** — a cache *miss* simply bills as ordinary input. Reads at the cheap rate. | DeepSeek official. Also used for every route that caches with free writes, *assuming the client drives it correctly*. |
| `none` | **No prompt caching.** All 10.0B cache reads *and* all 274M cache writes re-bill as full-price input. | Routes that expose no cache, and the failure mode of every `explicit` route whose client doesn't send breakpoints. |

Because no route in the slate charges a cache-**write** premium (only Qwen3 Coder Plus publishes one), `implicit` and "explicit-with-free-writes" produce identical arithmetic *when caching works*. The distinction that matters is not implicit-vs-explicit but **works vs doesn't** — which is why every row below carries both prices.

**Validation.** Before trusting a single candidate row, the engine was made to reproduce Phase 0's independently-computed Claude numbers from the same per-model token slices. It matches **to the cent** on all six models and both totals:

| | Engine | Phase 0 |
| --- | ---: | ---: |
| Intro prices (today) | $6,126.89 | $6,126.89 |
| Standard (from 2026-09-01) | $6,824.32 | $6,824.32 |

**Which baseline number is correct.** The Phase 0 *comment* on #151 says $6,167/mo; this document says $6,126.89. Both are right — the comment was re-measured ~6 minutes after `meter.json` was written and picked up 113 more messages (57,339 vs 57,226). The difference is 0.7%. Every figure here is priced against the **57,226-message profile** so all comparisons are same-basis.

---

## Full substitution — the whole workload on one model

Cheapest first. "Everything else" is input + cache write + output, so each row sums exactly. **"If caching fails"** prices the same route in `none` mode — what you pay if the cache silently doesn't engage.

| Candidate (route matters — see below) | **Cache read** | Everything else | **Total/mo** | If caching fails | Caching |
| --- | ---: | ---: | ---: | ---: | --- |
| **DeepSeek V4 Flash** — DeepSeek official | $28 | $49 | **$77** | $1,451 | **confirmed** |
| **DeepSeek V4 Pro** — DeepSeek official | $36 | $152 | **$189** | $4,507 | **confirmed** |
| Qwen3 Coder Next — OR→StreamLake | $360 | $83 | **$443** | $1,885 | unconfirmed |
| MiniMax M3 — OR→DeepInfra | $561 | $118 | **$679** | $2,921 | unconfirmed |
| DeepSeek V4 Pro — OR→Novita | $493 | $205 | **$698** | $6,051 | unconfirmed |
| MiniMax M3 — MiniMax official | $1,201 | $254 | **$1,456** | $6,261 | unconfirmed |
| DeepSeek V4 Pro — OR→DeepInfra | $1,001 | $455 | **$1,457** | $13,470 | unconfirmed |
| GLM-5.2 — OR→Decart | $1,201 | $266 | **$1,467** | $7,473 | unconfirmed |
| Claude Haiku 4.5 | $1,001 | $643 | **$1,644** | — | explicit |
| Kimi K2.7 Code — OR→DeepInfra | $1,361 | $313 | **$1,675** | $7,121 | unconfirmed |
| GLM-5.2 — OR→DeepInfra | $1,402 | $296 | **$1,697** | $7,804 | unconfirmed |
| DeepSeek V4 Pro — **opencode Zen** | $1,452 | $610 | **$2,061** | $18,029 | unconfirmed |
| *Hypothetical $0.20/MTok model* **(no caching)** | $0 | $2,087 | **$2,087** | — | **none** |
| Qwen3 Coder Next — OR→Novita **(no caching)** | $0 | $2,113 | **$2,113** | — | **none** |
| DeepSeek V4 Pro — OR→Together | $2,002 | $610 | **$2,612** | $18,029 | unconfirmed |
| Qwen3 Coder Next — OR→Alibaba **(no caching)** | $0 | $3,142 | **$3,142** | — | **none** |
| GLM-5.2 — Z.AI official | $2,603 | $549 | **$3,152** | $14,565 | unconfirmed |
| Grok 4.5 — xAI (<200K prompts) | $3,003 | $774 | **$3,778** | $20,796 | best-effort |
| Kimi K3 — Moonshot official | $3,003 | $1,382 | **$4,386** | $31,415 | unconfirmed |
| Claude Sonnet 5 (standard, from 09-01) | $3,003 | $1,928 | **$4,932** | — | explicit |
| Grok 4.5 — xAI (>200K prompts) | $3,003–$6,007 | $1,549 | **$4,552–$7,555** | $41,592 | best-effort |
| Claude Opus 5 (all-Opus hypothetical) | $5,005 | $3,214 | **$8,220** | — | explicit |
| **Claude — actual model mix (the baseline)** | **$3,787** | $2,340 | **$6,127** | — | explicit |

### Two results that justify the whole framing

**1. Caching beats headline price, decisively.** A hypothetical model at **$0.20/MTok with no caching costs $2,087/mo** — 11× *more* than DeepSeek V4 Pro at **$0.435/MTok with caching ($189/mo)**, despite a sticker price less than half. Shopping on the input-price column picks exactly wrong.

**2. The same model swings 7× on route alone.** Qwen3 Coder Next is **$443/mo** via StreamLake and **$3,142/mo** via Alibaba — identical model, identical tokens. The dominant difference is that one route caches and the other does not. On DeepSeek V4 Pro the spread is **11×** ($189 official → $2,061 via opencode Zen), because Zen resells at the Fireworks cache rate ($0.145) rather than DeepSeek's own ($0.003625) and offers **no route selection**.

Caching is the dominant term but not the only one — StreamLake is also cheaper on input ($0.18 vs $0.30) and output ($0.90 vs $1.50). Caching accounts for roughly $2,000 of the $2,699 gap; the rest is ordinary price difference.

> **This makes "which provider" the wrong question. The unit of choice is the *route*, and it must be pinned explicitly.** Default routing on an aggregator will not reliably land on the cheap endpoint.

**Fees on top, not included above.** OpenRouter adds a **5.5%** credit-purchase fee (5% crypto); opencode Zen adds **4.4% + $0.30/transaction**. So the `OR→` rows are ~5.5% higher than printed — Qwen3/StreamLake is ~$467 rather than $443, MiniMax/DeepInfra ~$717 rather than $679. Buying direct from DeepSeek carries no aggregator fee. The fee never changes a ranking here, but it is a real, sourced line.

### The "if caching fails" column is doing real work

Across all eight candidate models, OpenRouter's live endpoints API reports `supports_implicit_caching: true` on **only the two DeepSeek official routes**. Every Moonshot, Z.AI, xAI, Fireworks, Together, DeepInfra and Novita endpoint reports `false` — *including routes whose own docs describe caching as automatic*. The API and the documentation disagree, and this analysis cannot resolve which is right without an empirical test.

That is why the failure price is a column and not a caveat. If a route needs explicit `cache_control` breakpoints and the harness doesn't send them, the cost is not 10% higher — it is **4.3× to 9.2× higher**, and the two cheapest non-DeepSeek recommendations (Qwen3/StreamLake, MiniMax/DeepInfra) move from $443/$679 to $1,885/$2,921.

Note the asymmetry: DeepSeek official has the *largest* failure multiple (24×) precisely because its cached rate is so far below its input rate — but it is also the **only** route where caching is API-confirmed. Cheap-when-working and cheap-when-broken are different questions, and only DeepSeek currently answers the first with evidence.

**Before committing to any route, verify empirically that `cache_discount` is non-zero.** That single check is worth more than every price in this table.

### One more flag on the cheapest number in the survey

DeepSeek's cache-read price is **0.83% of its cache-miss price** for V4 Pro ($0.003625 vs $0.435). Historically DeepSeek's ratio was 10%, and every resale route in the table still charges 1/10th–1/12th. That is anomalous enough that the researchers flagged it twice, independently, with the instruction to **re-confirm on the live console before basing a decision on it**.

It was fetched three times from `api-docs.deepseek.com/quick_start/pricing` and read identically each time, and OpenRouter's live endpoints API passes the same figure through — so it is almost certainly the published price. But "published" and "what your invoice says at 10B tokens" are not the same claim, and this one number produces the $189/mo figure, the 32–79× gap, and recommendation #1. **Verify it against a real billed request before acting on it.** This is a separate risk from the announced price rise: that one is about future prices, this one is about whether the current number is real.

---

## Subscriptions — the arbitrage is closed

This is the most decision-relevant finding, and it is not about price at all.

**Cursor, GitHub Copilot, Devin/Windsurf, and Claude-with-extra-usage have all converged on the same billing model: a subscription that is a prepaid balance of provider list dollars, with overage at list.** On those four, a $6,127 workload costs about $6,127 no matter whose logo is on the invoice. The subscription buys $20–$400 of it.

| Plan | Price | Quota unit (vendor's own) | Month this workload serves | Effective cost to finish the month |
| --- | ---: | --- | ---: | ---: |
| Cursor Pro | $20 | $20 of API-agent usage | **~2.4 hours** | ~$6,127 |
| Cursor Pro+ | $60 | $70 included | **~8.2 hours** | ~$6,117 |
| Cursor Ultra | $200 | $400 included | **~1.96 days** | ~$5,927 |
| Copilot Pro | $10 | 1,500 AI credits ($15) | **~1.8 hours** | ~$6,122 |
| Copilot Pro+ | $39 | 7,000 credits ($70) | **~8.2 hours** | ~$6,096 |
| Copilot Max | $100 | 20,000 credits ($200) | **~0.98 days** | ~$6,027 |
| Devin/Windsurf Max | $200 | daily + weekly quota, **no numbers published** | `not found` | overage "at API pricing" ⇒ ~$6,127 |
| Z.ai GLM Max | ~$160 *(third-party)* | 28,000 credits/5h · 140,000/week | **~18 days** *(soft — see below)* | $160, no overage path |
| Kimi Vivace | $199 | "highest weekly plan quotas" — **no numbers published** | `not found` | reportedly unpurchasable since 2026-07-20 |
| ChatGPT Pro 20x + Codex | $200 | messages per rolling 5h window | **~50–100%** *(published quota is a 10× range)* | $200 |
| **Claude Max 5x — the incumbent** | **$100** | 5h session + weekly cap, **no numbers published** | `not found` | ~$6,127 with extra usage |
| Claude Max 20x | $200 | as above | `not found` | ~$6,127 with extra usage |

Only **OpenAI** (message-count windows) and **Z.ai** (prompt/credit windows) still meter in a unit a token-heavy workload can arbitrage — and both require changing model family, so neither is "the same workload" in any meaningful sense.

**How solid each "month served" figure is.** Where the vendor publishes *dollars* of included usage (Cursor, Copilot), the mapping to a dollar-denominated baseline is near-1:1 and the arithmetic is solid. Everything else needs an assumption, stated here rather than hidden:

- **ChatGPT Pro 20x** publishes a **10× range** (e.g. Terra 500–4,000 messages per 5h window). The workload needs ~397/window. At the top of the range it clears with headroom; at the bottom it serves ~50% of the month. "~100%" is the optimistic end only, and it also assumes even spread — a dispatcher fan-out that issues 397 requests in 20 minutes exhausts the window instantly regardless of the monthly total.
- **Z.ai's "~18 days"** is derived from a **third-party** prompt-per-window estimate, not from Z.ai's published credits — the credit→token conversion is unpublished (see Gaps). Treating one of the 57,226 API requests as one "prompt" is generous to Z.ai in one direction and hostile in the other. The same third-party source notes a **3× peak-hour multiplier** that would cut it to ~6 days. Treat the figure as an order of magnitude, not a number.

### Three things to be careful about here

- **The Cursor cache-read question is unresolved and it is the biggest single risk in this document.** Cursor's models page publishes input and output rates but no cached-token rate (`not found`, after checking the pricing, models, usage-limits, and pricing-policy pages). If Cursor does **not** pass through the ~10× cache-read discount, this workload on Cursor is not ~$5,927 — it is **~$31,000/mo**. The named "$60 Cursor tier driving Kimi K3 + Grok 4.5" therefore cannot be priced honestly today. Both models *are* available on Cursor (Kimi K3 at $3/$15 with full 1M context; Grok 4.5 inside the first-party pool), so the blocker is purely the missing rate.
- **Quota mapping requires an assumption in every case**, because no vendor meters in "cache-read tokens." Where a vendor publishes nothing at all (Devin, Kimi, Anthropic), the cell says `not found` rather than carrying a guess.
- **The incumbent has a terms problem that Phase 0 did not surface.** Anthropic's Claude Code legal page states: *"Advertised usage limits for Pro and Max plans **assume ordinary, individual usage** of Claude Code and the Agent SDK."* A 57,226-request/month heavy-fan-out multi-agent dispatcher is not obviously "ordinary, individual usage." The same page restricts OAuth to Anthropic's own clients and reserves enforcement **without prior notice**. This is not a breach finding — but "keep the $100 plan" rests on a clause the vendor has pre-emptively disclaimed, and that belongs next to the 61× savings. GitHub's AUP is blunter still ("excessive automated bulk activity"), and Copilot has a visible enforcement record.

---

## The hybrid — priced, and it disappoints

Issue #151 and the Phase 2 brief both expect a hybrid (cheap models for trivial/standard workers, Claude retained for deep work) to be the real answer. **Priced against this workload, it is not.**

Splitting the measured profile by the model that actually served it. **This section alone uses standard (post-2026-09-01) prices** — Sonnet 5's introductory rate expires in three weeks and a hybrid is a forward-looking decision, so comparing against the intro basis used elsewhere would flatter it. Against the intro basis ($6,127) the savings are ~5 points lower.

| Tier | Models | Cache reads | Cost on Claude |
| --- | --- | ---: | ---: |
| **Deep** | Opus 5 + Opus 4.8 | 5,926,802,891 | **$4,693** |
| **Cheap** | Sonnet 5, Sonnet 4.6, Haiku 4.5, Fable 5 | 4,084,205,497 | $2,131 |
| | | 10,011,008,388 | **$6,824** |

| Hybrid: Opus 5 + Opus 4.8 for deep, candidate for everything else | Cheap tier | **Hybrid total** | Saving vs $6,824 |
| --- | ---: | ---: | ---: |
| DeepSeek V4 Flash | $35 | **$4,729** | 31% |
| DeepSeek V4 Pro | $89 | **$4,782** | 30% |
| Qwen3 Coder Next (StreamLake) | $185 | **$4,879** | 29% |
| MiniMax M3 (DeepInfra) | $284 | **$4,977** | 27% |
| GLM-5.2 (Decart) | $618 | **$5,311** | 22% |
| Kimi K3 (Moonshot) | $1,864 | **$6,557** | 4% |

**The deep tier alone is $4,693 — 69% of the all-Claude bill.** So even moving *100% of everything else* to the cheapest credible provider saves only ~30%. Like for like on the same model, full substitution to DeepSeek V4 Pro is **$189** against the hybrid's **$4,782** — 25× cheaper — because the hybrid keeps precisely the expensive part.

**A premise worth correcting while we're here.** The brief describes this workload as coming from "Opus/**Fable**-heavy dispatcher fan-outs." The data does not support the Fable half: Fable 5 is **$29.11 of $6,126.89 — 0.5% of the bill**, on 110 messages out of 57,226. It sits in the "cheap" tier above purely because it is negligible, not because it is cheap (at $10/$50/$1.00 it is the most expensive model in the entire survey, twice Opus). The workload is Opus- and Sonnet-heavy; Fable is a rounding error.

This is worth stating plainly because it inverts the brief's expectation: **the hybrid is not a cost strategy.** If the goal is to cut cost, the lever is the Opus-tier cache reads, not the Sonnet-tier ones. The hybrid remains defensible as a *quality* strategy — pay for Opus where it matters, stop paying for it where it doesn't — but it should be argued on those grounds, not on this table.

---

## Harness compatibility on this machine

Checked directly on `mbp-m4-pro`, 2026-08-10:

| Harness | Present | Notes |
| --- | --- | --- |
| `claude` (Claude Code) | ✅ | The incumbent. Hooks, five plugins, statusline, skills and MCP wiring are all built against it. |
| `opencode` | ✅ | Configured with a local `Lemonade` provider today. Accepts arbitrary OpenAI-compatible providers. |
| `cursor-agent` | ✅ | Installed, but the dispatcher's cursor engine is gated to the work profile (`programs.dispatcher.profile`). |
| `codex`, `crush`, `pi`, `gemini`, `aider` | ❌ absent | Would need adding before they could be trialled. |

| Candidate | Reachable how | Verdict |
| --- | --- | --- |
| **DeepSeek** | OpenAI-compatible API key → `opencode` | ✅ Clean. No reverse engineering, no vendor lock. |
| **OpenRouter** | OpenAI-compatible key → `opencode`; `provider.order` **must** be pinned | ✅ Clean, with mandatory route pinning. |
| **Z.ai GLM** | Anthropic-compatible coding endpoint; **officially documents Claude Code / OpenCode / Cline support** | ✅ Best-in-class — the only vendor that *documents* third-party CLI use as supported. |
| **Moonshot / Kimi** | OpenAI- and Anthropic-compatible API keys | ✅ For API credit. Whether the *subscription* quota is reachable from a third-party CLI: `not found`. |
| **opencode Zen** | Native to `opencode` | ⚠️ Works, but no route selection ⇒ locked to Fireworks-tier cache pricing. |
| **Cursor** | `cursor-agent -p`, plus a Beta Cloud Agents API/SDK | ⚠️ Third-party CLIs proxy Cursor's gRPC API, which runs into the ToS reverse-engineering clause. Not a safe basis for a plan. |
| **GitHub Copilot** | Official CLI; `opencode`'s `github-copilot` provider via OAuth token | ❌ AUP names "excessive automated bulk activity" — exactly this pattern. |
| **Devin/Windsurf** | Vendor-locked | ❌ No documented third-party CLI path. |

---

## What breaks

- **Context window.** This profile came from sessions large enough to accumulate 10B cache reads. Routes that silently truncate context are disqualified for that work regardless of price: Together serves DeepSeek V4 Pro at **512K** (not 1M) and GLM-5.2 at 512K; BaseTen at **262K**; AkashML serves GLM-5.2 at **96,890 tokens**. On OpenRouter, GLM-5.2's model-level context is 1M but `top_provider.context_length` is **262K** — default routing lands on the smaller endpoint.
- **Tool calling — a hard disqualifier where absent.** Chutes' and DeepInfra's **Kimi K3** endpoints and GMICloud's **MiniMax M3** endpoint report `tools: false` on OpenRouter's live API. An agentic dispatcher cannot use them at any price. GMICloud's M3 is otherwise the cheapest M3 route.
- **Caching that is advertised but not delivered.** See the "if caching fails" column above — the single largest modelling risk in this document.
- **Probabilistic caching.** xAI documents that Grok's cache is best-effort: entries evict under memory pressure and requests may route to a different server, with no hit guarantee even using `x-grok-conv-id`. A miss re-bills at $2–4/MTok, 6.7× the cached rate within a tier.
- **Long-context price cliffs.** Grok 4.5 doubles input and output above 200K prompt tokens, and that threshold sits *below* its own 500K window. Whether the *cached* rate also doubles is `not found` on xAI's docs (one aggregator asserts $0.60; the first-party page does not confirm it), which is why that row is a **range, $4,552–$7,555**. Qwen3 Coder Plus tiers by request size and triples its cache-read rate above 128K.
- **Announced price rises.** DeepSeek's own pricing page carries the verbatim warning: *"We plan to raise the overall pricing for DeepSeek API services in the near future, with a significant increase expected."* **The cheapest option in this entire survey is explicitly flagged as temporary.** Anthropic's Sonnet 5 introductory pricing expires **2026-08-31**, which is why the standard-price column exists throughout.
- **Data residency and training terms.** DeepSeek, Z.AI, Moonshot and MiniMax are all `headquarters: "CN"` per OpenRouter's providers API. DeepSeek's privacy policy describes an opt-out right but no mechanism, and documents no zero-retention tier. xAI offers a genuine Zero Data Retention API and states it does not train foundation models on API content. Anthropic does not train on API inputs by default. Retention for DeepInfra, Fireworks, Together, Novita and Chutes: `not found`.
- **Rate limits and concurrency.** At 57,226 requests/month against a dispatcher that fans out in bursts, the binding constraint is often concurrency rather than monthly volume. DeepSeek publishes **500 concurrent requests** account-wide on V4 Pro; **DeepInfra caps at 200 concurrent per account** — a hard ceiling on any fan-out wider than that. xAI is spend-tiered (150→500 RPS, 50–100M TPM) and, critically, **cached tokens still count toward TPM**, so a 97%-cache-read workload consumes the token budget at full rate even while paying the cached price. Moonshot tiers RPM/TPM by cumulative recharge. Together, Fireworks, Novita and Chutes publish no rate limits (`not found`).
- **Structured output.** Every priced candidate documents OpenAI-compatible function calling and JSON/schema output: DeepSeek (`tools`, `tool_choice`, `response_format`), xAI (function calling + structured outputs), Qwen-Coder, MiniMax, and Anthropic (`strict: true` schema enforcement, parallel tool use). The exception is the endpoint level, not the model level — see the `tools: false` routes above. No candidate is disqualified on structured output *as a model*; several are disqualified on it *as a route*.
- **Tokenizer drift.** Opus 4.7+ and Sonnet 5 use a newer tokenizer producing ~30% more tokens for the same text, so even the Claude-internal comparison is not perfectly like-for-like across generations — another reason to treat these as floors.

---

## Recommendation

**Do not switch on the strength of this document.** It prices tokens; it does not measure whether the work gets done. But it narrows the field from a dozen candidates to **three worth trialling**, and disqualifies several outright.

**Worth trialling, in order:**

1. **DeepSeek V4 Pro via the official route** (~$189/mo; ~$77 on V4 Flash). The gap to Claude is 32–79×. It is the **only** route in the slate whose implicit caching OpenRouter's live API confirms, and it has 1M context, tool calling, and a clean path into `opencode`. *Trial must prove:* merge-ready rate on the Phase 1 suite, that real cache-hit rates hold outside a benchmark, and that the $0.003625 cache-read rate survives contact with a real invoice. *Risks to price in:* the announced price rise, and CN data residency.

   A tempting argument to **not** make: "the gap is 32–79×, so even a model needing 3× the turns lands near $570 and still wins." The arithmetic is right and the reasoning is wrong. Turn count is not the only thing that moves — a weaker model reshapes the token profile rather than scaling it, and the costs that actually bite (rework, review time, a wrong answer that ships) are invisible to $/token entirely. A large margin makes the candidate *worth testing*; it does not make the test optional.
2. **Qwen3 Coder Next via a pinned cheap route, or MiniMax M3 via DeepInfra** (~$443 / ~$679 **if caching works**; $1,885 / $2,921 if it doesn't). The insurance policy if DeepSeek's price rise lands or CN residency is disqualifying. *Trial must prove, before anything else:* that `cache_discount` is non-zero on the pinned route. Until that is measured these two rows are the least trustworthy in the table.
3. **Z.ai GLM coding plan.** Price and capacity are both soft: the ~$160/mo Max figure is **third-party**, and the "serves ~18 days" estimate rests on a third-party prompt proxy that drops to **~6 days** under the reported 3× peak-hour multiplier. What makes it worth a trial anyway is not the economics — it is that Z.ai is the **only** vendor here that *documents* Claude Code and OpenCode support, so trying it costs almost no engineering. Treat it as the cheapest available answer to "is a non-Claude model good enough at all, on the harness I already have?" rather than as a costed plan. *Trial must prove:* quality at the $18 Lite tier before paying for anything above it.

**Disqualified without further work:** Copilot (AUP names "excessive automated bulk activity", with an enforcement record), Devin/Windsurf (vendor-locked, no published quotas at any tier), Kimi subscriptions (reportedly unpurchasable since 2026-07-20, and the coding benefit is being split into a separate unpriced product), opencode Zen *for this workload specifically* (no route selection ⇒ 11× penalty on the dominant cost line), any Qwen route without caching, and — for agentic use — the Kimi K3 and MiniMax M3 endpoints that report `tools: false`.

**Two candidates named in the brief that this document does not carry forward, and why:**

- **Chutes** is not priced as a candidate. Its subscription tiers ($10 Plus / $20 Pro) publish only "bundled" and "larger" daily quotas — no numbers, so no feasibility arithmetic is possible — and its per-token coverage surfaced only for TEE variants (GLM-5.2 $1.25/$3.95/$0.125, Kimi K3 $3.00/$15.00/$0.30, DeepSeek V4 Flash 0731 $0.14/$0.28/$0.014), which are no cheaper than routes already in the table. Its Kimi K3 endpoint also reports `tools: false`. **Not a disqualification on the merits — a `not found` on the numbers that would decide it.** Same for **Fireworks** and **Together** as standalone vendors: both appear in the table via their OpenRouter routes, and neither is competitive there.
- **ChatGPT Pro 20x + Codex** is the one subscription whose quota might genuinely absorb this volume, and it is deliberately *not* recommended. Two reasons: its published quota is a **10× range**, so "fits" and "runs out mid-month" are both consistent with the documentation; and the 5-hour rolling window is structurally hostile to burst fan-out — 397 requests in twenty minutes exhausts a window that a monthly average says is fine. It also means changing model family entirely, which is a different decision from the one this issue is asking. **Worth revisiting if the burstiness question is ever measured** — it is the only remaining subscription arbitrage on the market.

**Blocked on a missing fact:** Cursor. Get the cache-read rate — from support if the docs won't say — before pricing it. The answer moves it between ~$5,927 and ~$31,000/mo, which is the difference between "marginal" and "absurd."

**On the incumbent.** Phase 0's verdict (keep the $100 plan; the metered equivalent is ~61×) is unchanged and unchallenged by anything here — no subscription on the market serves this volume for less, and the four biggest have closed the arbitrage entirely. The one new consideration is the "ordinary, individual usage" clause: the current economics depend on a plan whose terms are written to exclude workloads shaped like this one. Worth knowing whether or not anything changes.

**What would actually change the answer:** Phase 1. Every number here is a floor under an unmeasured quantity. A trial that measures **$/merge-ready task** on 15–25 real PRs, from the same parent commits, is the only thing that converts this from a price list into a decision.

---

## Sources

All fetched **2026-08-10**. First-party unless marked.

**Model pricing:** [DeepSeek](https://api-docs.deepseek.com/quick_start/pricing) · [DeepSeek KV cache](https://api-docs.deepseek.com/guides/kv_cache) · [Moonshot Kimi K3](https://platform.kimi.ai/docs/pricing/chat-k3) · [Moonshot caching](https://platform.kimi.ai/docs/guide/use-context-caching-feature-of-kimi-api.md) · [Z.ai](https://docs.z.ai/guides/overview/pricing) · [MiniMax](https://platform.minimax.io/docs/api-reference/text-prompt-caching) · [Alibaba Model Studio](https://www.alibabacloud.com/help/en/model-studio/model-pricing) · [Alibaba context cache](https://www.alibabacloud.com/help/en/model-studio/context-cache) · [xAI models](https://docs.x.ai/docs/models) · [xAI prompt caching](https://docs.x.ai/developers/advanced-api-usage/prompt-caching/how-it-works) · [xAI rate limits](https://docs.x.ai/developers/rate-limits) · [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing)

**Aggregators:** OpenRouter live `/api/v1/models` and `/api/v1/models/{id}/endpoints` · [OpenRouter prompt caching](https://openrouter.ai/docs/features/prompt-caching) · [OpenRouter FAQ](https://openrouter.ai/docs/faq) · [opencode Zen](https://opencode.ai/docs/zen) · [DeepInfra](https://deepinfra.com/pricing) · [Fireworks](https://fireworks.ai/pricing) · [Together](https://together.ai/pricing) · [Novita](https://novita.ai/pricing) · [Chutes](https://chutes.ai/pricing) · models.dev `api.json` *(community-maintained; used only where vendor pages were incomplete, cross-validated against OpenRouter's live API on six overlapping rows — matched exactly each time)*

**Subscriptions:** [Cursor pricing](https://cursor.com/docs/account/pricing) · [Cursor usage limits](https://cursor.com/help/models-and-usage/usage-limits) · [Cursor models](https://cursor.com/docs/models) · [Cursor ToS](https://cursor.com/terms-of-service) · [Copilot plans](https://docs.github.com/en/copilot/concepts/billing/individual-plans) · [Copilot models & pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing) · [GitHub AUP](https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies) · [Devin pricing](https://devin.ai/pricing) · [Z.ai devpack](https://docs.z.ai/devpack/overview) · [Kimi Code pricing](https://www.kimi.com/resources/kimi-k2-7-code-pricing) · [Claude Max](https://support.claude.com/en/articles/11049741-what-is-the-max-plan) · [Claude Code legal](https://code.claude.com/docs/en/legal-and-compliance) · [ChatGPT pricing](https://learn.chatgpt.com/docs/pricing)

### Gaps — stated rather than estimated

Per the research constraint, these were **not** filled with a guess:

| Missing | What was tried |
| --- | --- |
| **Cursor cache-read / cache-write rates** | Pricing, models, usage-limits, and pricing-policy pages. The highest-value open question here. |
| Cursor "Cursor Models" pool numeric cap | Only "generous included usage" published. |
| Devin/Windsurf numeric quotas, all tiers | `windsurf.com/pricing` 308-redirects to `devin.ai/pricing`; `docs.devin.ai/plans-and-pricing` 404s. Cognition publishes no numbers. |
| Kimi numeric quotas, all tiers | Tiers described only as "ample" / "expansive" / "highest". |
| Chutes daily quota sizes (Plus/Pro), caching support, non-TEE PAYG rates | `chutes.ai/pricing` — described only as "bundled"/"larger". This is why Chutes is unpriced rather than disqualified. |
| Z.ai Pro/Max USD prices | `z.ai/subscribe` renders client-side; docs give only "starting at $18" plus 6×/14× multipliers. The $72/$160 figures are **third-party**. |
| Z.ai credit→token conversion | 5h/weekly credit caps are official; the credit definition is not. The "~18 days" figure rests on a third-party prompt proxy. |
| Anthropic numeric limits for Pro / Max 5x / Max 20x | Five support articles. Anthropic publishes relative multipliers only — a deliberate non-disclosure, not a search failure. |
| OpenAI credit dollar value | Credits-per-MTok published; the price of a credit is not. |
| xAI cached-token rate above the 200K threshold | First-party docs confirm input/output double but are silent on the cached rate; one aggregator asserts $0.60. Priced as a range. |
| Fireworks / Novita caching mechanics (implicit vs explicit, TTL) | Docs say only that cached input is "priced lower". Novita's caching guide 404s. |
| Retention/training terms for DeepInfra, Fireworks, Together, Novita, Chutes | Pricing pages and OpenRouter's providers endpoint, which exposes only HQ and policy URLs. |
| DeepSeek cache TTL / eviction policy / minimum cacheable prefix | Prices confirmed; mechanics not stated. |
| Kimi "sold out" status | Third-party reports dated 2026-07-20; kimi.com showed no marker on fetch. **Unconfirmed.** |

**Source conflict, disclosed:** MiniMax M3's own pricing page gives $0.60/$2.40/$0.12, while OpenRouter's live data for MiniMax's *own* endpoint gives exactly half ($0.30/$1.20/$0.06 → $728/mo rather than $1,456). The first-party figure is used above as the conservative choice; the cheaper OpenRouter reading would move that row up the table.

**Negative finding (not a gap):** DeepSeek's off-peak discount window is confirmed **absent** from the current pricing page.
