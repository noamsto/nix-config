# Stinger Handle/Stand Design

**Date:** 2026-01-27
**Status:** Ready for prototyping

## Overview

A removable 3D-printed accessory for the Tynee Stinger e-skateboard that serves as:

1. **Handle** — ergonomic grip for carrying ~13kg up stairs
2. **Stand** — stable rear support with folding arms

## Use Cases

- Rolling board on front wheels (short to medium distances)
- Carrying up/down stairs (full lift)
- Parking the board upright (stand mode)
- Quick attach/detach — not left on during riding

## Constraints

| Constraint                | Value | Notes                    |
| ------------------------- | ----- | ------------------------ |
| Center gap between motors | 42mm  | Main attachment zone     |
| Motor clearance (sides)   | <7mm  | No-go zone               |
| Board weight              | ~13kg | Must support full weight |

## Measured Dimensions

### Bracket Bars

| Measurement                        | Value  |
| ---------------------------------- | ------ |
| Bar diameter                       | 10mm   |
| Bracket width (no screws)          | 162mm  |
| Upper bars spacing (center-center) | 30mm   |
| Upper to lower bar vertical drop   | 23mm   |
| Lower bar outward offset           | 21.5mm |

### Bar Geometry (side view)

```
○───30mm───○         upper bars (near deck)
            \
             \  23mm vertical
              \
               ○     lower bar (21.5mm outward toward wheel)
```

### Deck

| Measurement             | Value  |
| ----------------------- | ------ |
| Deck width at rear      | 170mm  |
| Deck edge thickness     | ~14mm  |
| Bar to deck edge height | 87.5mm |

## Design

### Saddle Body

- **Width:** 40mm (fits 42mm motor gap)
- **Length:** ~60mm (spans upper bars + hook reach)
- **Top surface:** Flat, contacts both upper bars (30mm span)
- **Hook:** Angled leg extending 23mm down, 21.5mm out to capture lower bar
- **Hook inner diameter:** 11mm (10mm bar + 1mm clearance)

### Side Guides

- **Span:** 162mm (matches bracket width)
- **Function:** Contact mounting brackets to prevent lateral movement
- **Note:** Must not extend into <7mm motor clearance zone

### T-Handle

- **Width:** 120mm (comfortable two-hand or one-hand grip)
- **Diameter:** 25-30mm (ergonomic for 13kg load)
- **Position:** Centered above saddle

### Folding Arms

- **Pivot:** At sides of saddle body
- **Length:** ~95mm (reaches 87.5mm + cradle depth)
- **Spread (deployed):** 170mm (matches deck width)
- **Detent:** Click-lock at 90° deployed position
- **Deck cradle:** 15mm wide slot, 14mm deep

### Assembly (side view)

```
        ┌───────────────┐
        │   T-HANDLE    │
        └───────┬───────┘
                │
        ┌───────┴───────┐
        │    SADDLE     │ ← flat on upper bars
        │               │
        └───────┬───────┘
                 \
                  \      ← angled leg
                   ╰─╮
                     │   ← hook under lower bar
```

### Assembly (front view)

```
Folded:                          Deployed:
        ┌─────────┐                      ┌─────────┐
        │ HANDLE  │                      │ HANDLE  │
        └────┬────┘                      └────┬────┘
      ┌──────┴──────┐                  ┌──────┴──────┐
      │ARM│SADDLE│ARM│              ╱──│    SADDLE   │──╲
      └─────────────┘              ╱   └─────────────┘   ╲
      │side│    │side│           ARM                     ARM
      │guid│    │guid│            │╭─────╮       ╭─────╮│
      └────┘    └────┘            ││deck │       │deck ││
                                  │╰─────╯       ╰─────╯│
                                  │  cradle       cradle│
```

## Print Recommendations

| Setting        | Value       | Reason                 |
| -------------- | ----------- | ---------------------- |
| Material       | PETG or ABS | Strength + flexibility |
| Infill         | 40-60%      | Structural load        |
| Wall thickness | 2-3mm       | Durability             |
| Layer height   | 0.2mm       | Balance speed/quality  |

### Print Orientation

- Saddle body: Flat (hook may need supports)
- Arms: Flat or print separately
- Consider splitting into parts and assembling with pins/screws

## Iteration Notes

This is v1 — expect to iterate on:

- Hook fit (may need adjustment for snug vs easy release)
- Arm detent strength (too weak = sag, too strong = hard to deploy)
- Handle position (may need angle adjustment)
- Side guide width (balance stability vs motor clearance)

## Reference Images

- `/home/noams/Downloads/IMG_5489_small.jpg` — rear view showing motors and bracket
- `/home/noams/Downloads/IMG_5490_small.jpg` — side view showing bar geometry
- `/home/noams/Downloads/Protection-Bracket-For-Tynee-Explorer-Electric-Skateboard_600x.webp` — original bracket product image
