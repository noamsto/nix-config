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
| 4 | `len()` for column math | Display cells ≠ bytes. Use `lipgloss.Width` / `ansi.StringWidth`, never `len()`. |
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

## Notes

- For framework basics (Elm architecture, `Update`, widgets) this skill is not the place — it is purely about layout correctness.
