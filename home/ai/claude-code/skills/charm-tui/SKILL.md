---
name: charm-tui
description: Use when writing or editing a Bubble Tea / Lipgloss terminal UI in Go — any View()/render function, bordered panel or box layout, column alignment, viewport sizing, or when a TUI shows border bleed, content overflowing its frame, misaligned columns, color/style bleed, or breaks on window resize. Applies to charmbracelet/bubbletea, bubbles, lipgloss (v1 and v2).
---

# Charm TUI Layout Correctness

## Overview

Bubble Tea/Lipgloss make the same ten layout mistakes easy to write and hard to see. This skill is the antidote list, grounded in the recurring bugs across Noam's own TUIs (prdash, wtc, tmux-state) plus upstream gh-dash.

**The one root cause behind most of them:** `lipgloss.Style.Width(W)` and `.Height(H)` set the size of the box *including* its own border and padding, and they only **pad up** to that size — they never clip. So content sized to the outer width overflows, and the border gets pushed off-screen. Everything below follows from taking that seriously.

## The box model (internalize this)

```
Style.Width(W)  ─────────────── W cells total ───────────────
                │ border │ pad │      content       │ pad │ border │
                                └ usable = W − GetHorizontalFrameSize() ┘
```

- `Width`/`Height` count border + padding against the total and **pad, never clip**.
- Margins sit *outside* `Width(W)` and add to the on-screen footprint.

## Quick reference — the ten traps

| # | Trap | Rule → idiom |
|---|------|--------------|
| 1 | Border bleed / early wrap (the "−N tax") | Inner size = outer − `style.GetHorizontalFrameSize()` / `GetVerticalFrameSize()`. Measure sibling widgets with `lipgloss.Height/Width(rendered)` — **never** hand-subtract `w-2`/`w-4`. |
| 2 | `Width/Height` pad but don't clip | Pair every `Width`/`Height` with `MaxWidth`/`MaxHeight`, or `ansi.Truncate` the content yourself. |
| 3 | Untruncated variable-width string | `ansi.Truncate(s, innerW, "…")` every string you don't control (titles, labels, paths). **Never auto-wrap inside a bordered panel** — truncate or pan. |
| 4 | `len()` for column math | Display cells ≠ bytes. Use `lipgloss.Width` / `ansi.StringWidth`, never `len()`. For emoji/CJK there's a real fix — see the width note below. |
| 5 | ANSI style bleed | One style layer per span: render the **plain** string once with the bg style; never nest a `.Render()`-ed span inside another background. Strip non-SGR escapes (cursor/OSC/bracketed-paste) from captured pty/tmux content before framing — they corrupt the border. If you slice reset codes by hand, match **both** `\x1b[0m` and `\x1b[m` (v2 emits the short form). |
| 6 | Unclamped derived dimension | `max(0, …)` every subtraction before it reaches a style, viewport, or `strings.Repeat` — terminals can be 1 column wide. |
| 7 | Chrome height not reserved | Subtract footer/header height **once** (measured with `lipgloss.Height`), pass an explicit `Height` into every child; don't let a `JoinVertical` child size itself. |
| 8 | Magic-number drift | Derive a shared dimension (gutter width, inner height) from one helper/const — never re-literal it in a second render path. |
| 9 | Scroll clamp / off-by-one | Clamp offset to `[0, max(0, contentH−visibleH)]`; window by counting *emitted display lines* (headers included), not `index×rowHeight`; test the `==` boundary. |
| 10 | Header ↔ row contract | Adding/removing/hiding a column must touch the header builder, the row builder, **and** every layout mode, or the table shears. |

## Correct bordered panel (the antidote)

```go
var (
	panel    = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).Padding(0, 1)
	titleSt  = lipgloss.NewStyle().Bold(true)
	selected = lipgloss.NewStyle().Background(lipgloss.Color("62")).Foreground(lipgloss.Color("230"))
	footerSt = lipgloss.NewStyle().Faint(true)
)

func (m Model) View() string {
	if m.width == 0 {
		return "" // no WindowSizeMsg yet — never render at a bogus size
	}

	footer := footerSt.Render("↑/↓ navigate • q quit")

	// Trap 7: reserve chrome by MEASURING the footer, not guessing a constant.
	outerH := max(0, m.height-lipgloss.Height(footer))
	box := panel.Width(m.width).Height(outerH)

	// Trap 1: interior = outer − the frame THIS style adds. No hand-rolled -2/-4.
	innerW := max(0, m.width-box.GetHorizontalFrameSize())   // Trap 6: clamp
	innerH := max(0, outerH-box.GetVerticalFrameSize())

	var b strings.Builder
	b.WriteString(ansi.Truncate(titleSt.Render("Items"), innerW, "…")) // Trap 3
	b.WriteByte('\n')

	// Trap 9: window to the rows that fit (title took one). visibleRows clamps the offset.
	for i, it := range m.visibleRows(max(0, innerH-1)) {
		line := ansi.Truncate(it.text, innerW, "…") // Traps 3 & 4 (ansi = display-width)
		if it.selected {
			// Trap 5: one style layer — style the plain, padded line once.
			line = selected.Width(innerW).Render(ansi.Truncate(it.text, innerW, "…"))
		}
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(line)
	}

	// Trap 2: MaxHeight hard-clips so a long body can't shove the bottom border off-screen.
	body := box.MaxHeight(outerH).Render(b.String())
	return lipgloss.JoinVertical(lipgloss.Left, body, footer)
}
```

## Red flags — stop and re-check

- `- 2` / `- 4` / any magic number in width/height math → use `GetHorizontalFrameSize()`/`GetVerticalFrameSize()`.
- `len(someDisplayString)` → `lipgloss.Width` / `ansi.StringWidth`.
- `.Width(x)` with no matching `.MaxWidth`/truncation, or content that can exceed the box.
- `strings.Repeat(sep, w - k)` without a `max(0, …)` guard.
- A `.Render()`-ed string passed as input to another `.Render()` that sets a background.
- Two render paths that both hardcode the same spacing/gutter.
- The same "height − footer − border" arithmetic copy-pasted in 3 places.

## More gotchas (beyond the core ten)

- **Blank / wrong-size screen.** Guard `if m.width == 0 { return "" }` — the first frame arrives before any `WindowSizeMsg`. And let Bubble Tea own the controlling TTY: don't `tea.WithOutput(os.Stderr)`, it misroutes the size queries and the program never learns its dimensions (renders blank in a tmux popup).
- **Overlay / modal anchoring.** Anchor a floating layer to a **fixed edge** (e.g. top at `h/5`), not to a vertical center that shifts every time the content grows — a centered overlay jumps around by height.
- **Wrap vs pan is a per-pane decision.** Never both wrap *and* truncate the same content. When full lines matter (diffs, tables), disable wrapping and pan horizontally (`ansi.Cut`, viewport `SetHorizontalStep`); only the narrow quick-view wraps.
- **Don't rebuild per frame.** Memoize expensive renderers (glamour `NewTermRenderer`) by wrap-width — `View()` runs every keystroke. On `WindowSizeMsg`, **resize** a viewport, don't reconstruct it.
- **Rune vs byte indexing (caret/token math).** `textinput.Position()` is rune-indexed; convert at byte-scan boundaries or a multibyte prefix (Hebrew, emoji) slices mid-rune and misplaces the caret. Distinct from trap 4 (that's display *width*; this is string *indexing*).
- **Footer/help hints from the keymap.** Derive hint labels from the same key constants the handler binds — a hardcoded `i:idle` lies the moment the binding moves to `s`.
- **Color vanishes in tests / pipes.** Lipgloss auto-detects the color profile and **strips all color when stdout isn't a TTY** (CI, pipes, snapshot tests) and downsamples on a plain linux tty / over SSH. For deterministic golden tests, force it: `lipgloss.SetColorProfile(termenv.TrueColor)` (v1). Don't force it in the app — let it degrade.
- **Join-axis confusion.** `JoinHorizontal` takes a *vertical* position (`Top`/`Bottom`/0–1); `JoinVertical` takes a *horizontal* one (`Left`/`Right`). Passing `Left` to `JoinHorizontal` (or `Top` to `JoinVertical`) silently mis-aligns blocks of unequal size.
- **Center with `Place`, not math.** `lipgloss.Place(w, h, lipgloss.Center, lipgloss.Center, content)` fills a known box with whitespace around content — prefer it over hand-rolled centering (and it pairs with fixed-edge overlay anchoring).

## The truncation import (get this exact — it is the #1 hallucination)

**There is no `lipgloss.Truncate`.** Display-width truncation lives in `github.com/charmbracelet/x/ansi`:

```go
import "github.com/charmbracelet/x/ansi"

ansi.Truncate(s, width, "…")   // clip to `width` display cells, append tail
ansi.StringWidth(s)            // display-cell width (use over len())
ansi.Cut(s, left, right)       // horizontal window for panning
ansi.Wrap(s, limit, "")        // wrap when you deliberately want wrapping
```

`lipgloss.Width` / `lipgloss.Height` measure already-rendered blocks (for reserving chrome). Legacy stacks may use `github.com/muesli/reflow/truncate` instead — but never a bare `lipgloss.Truncate`; it does not exist.

## Emoji & CJK width — the real fix

The default `ansi.StringWidth` / `ansi.Truncate` / `ansi.Cut` are **already grapheme-cluster-aware** (they use `GraphemeWidth` + `FirstGraphemeCluster`), so they measure ZWJ emoji and combining marks correctly. They *are* the fix — you don't need anything extra. What breaks alignment is reaching for a per-rune path instead:

- ❌ `len(s)`, `utf8.RuneCountInString(s)`, `runewidth.RuneWidth` summed in a loop, or the `*Wc` variants (`ansi.StringWidthWc`, `ansi.TruncateWc`) — these count a grapheme cluster as several cells.
- ✅ the default `ansi.*` functions (or `rivo/uniseg.StringWidth` directly).

**Irreducible residual — the border-misalignment bug.** lipgloss commits to a width from its Unicode table; the *terminal* has the final say on what it actually paints, and the two can disagree by 1 cell — shifting a bordered box's right edge on that line. But the disagreement is narrower than "all emoji," and it is **font/terminal-specific — measure your own stack, don't assume:**

- On a modern stack (kitty + tmux built with utf8proc + `variation-selector-always-wide on`), most emoji **agree at 2 and align** — verified: `❤️ ⚠️ ✔️`, flags (`🇮🇱`), ZWJ family (`👨‍👩‍👧`), CJK all rendered flush.
- The residual is **VS16 emoji whose base is a text-default dingbat** (`✍️` U+270D, `✂️`, `✒️`, `✏️`): lipgloss says 2, but if the terminal **font has no wide color glyph** it paints a monochrome text glyph at **1** → 1-cell drift. Font-coverage-dependent, so it varies by machine.
- On **older/simpler stacks** (or tmux without utf8proc / VS16-wide off) the split is wider — plain wcwidth paints `❤️` and flags at 1 too.

Confirm on *your* stack: render the suspect glyphs in a bordered box (or a padded-then-marker row) and see which right edges drift; don't theorize. Mitigations, in order:
1. **Strip VS16** (`strings.ReplaceAll(s, "️", "")`) from title/body *source* before rendering — drops lipgloss's count to 1, matching a text-presentation terminal, so the border aligns (cost: monochrome glyph). Verified fix; doesn't help flags.
2. **Keep ambiguous-width glyphs out of load-bearing bordered content**, or reserve a cell of slack.
3. Terminal-side is mostly a dead end: kitty `symbol_map` changes the *font*, not the cell width (won't move the border); `narrow_symbols` only forces glyphs *narrower*; tmux `codepoint-widths "U+270D=2"` can force a specific codepoint wide but is per-glyph whack-a-mole. The purpose-built fix — kitty's text-sizing protocol (OSC 66) — works kitty-direct but **tmux upstream declined to support it** (issue #4461, closed "very little chance"), and Mode 2027 negotiation is likewise unavailable through tmux. So inside tmux there is no robust protocol fix; strip-VS16 (option 1) is the reliable lever.

## Notes

- For framework basics (Elm architecture, `Update`, widgets) this skill is not the place — it is purely about layout correctness.
