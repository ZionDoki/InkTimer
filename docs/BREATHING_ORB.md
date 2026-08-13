# Breathing Orb Animation

Technical notes on the morphing orb implementation.

## Problem

The original Svelte version had a living, morphing outline using CSS `border-radius` animation. The initial Flutter port used a static path that never changed shape.

## Solution

**Modulate the hand-tuned control points instead of rebuilding the shape.**

The orb outline is defined by 13 anchor points forming 4 cubic Bézier segments. Each point is scaled radially based on its angle:

```dart
double radialMod(double angle) =>
    sin(angle * 2 + time) * 0.0075 +
    sin(angle * 3 - time * 2) * 0.0045;
```

This preserves the original asymmetric shape while adding subtle organic motion.

## Four Rules

The first attempt violated these rules and produced visible seams and jumps:

| Rule | Why |
|------|-----|
| Angular frequencies must be integers | Non-integer frequencies create a seam at the closure point where `noise(0) ≠ noise(2π)` |
| Time multipliers must be integers | The animation controller wraps from 1.0 to 0.0; non-integer multipliers cause a visible snap every cycle |
| Amplitude must be subtle | The goal is "breathing," not "writhing" |
| No rotation component | The water surface must stay horizontal |

The old implementation used frequencies `3.2 / 5.7 / 8.1` with time multipliers `1.7 / 2.3 / 0.9`:
- Spatial seam: 1.7–2.5% radius jump
- Temporal snap: up to 5.4% radius jump every 11 seconds
- Peak-to-peak amplitude: 9.74% (4× current)

Current implementation measured: spatial seam 0.00%, temporal snap 0.00%, amplitude 2.40%.

## Implementation

- `_OrbMorphNotifier` holds an independent 11-second animation controller with random initial phase
- Both `_OrbShellPainter` and `_FluidPainter` subscribe to the same notifier, ensuring water and shell stay synchronized
- The shadow uses a static path (18px blur + 5.5% offset) — the subtle morph falls within the blur radius
- Path is cached by `(size, phase)` — paused animations hit the cache every frame

## Parameters

| Parameter | Value | Note |
|-----------|-------|------|
| Breathe period | 7000ms | Matches Svelte |
| Breathe amplitude | ±3.2% | Close to Svelte's ±3.5% |
| Morph period | 11000ms | Incommensurate with 7s → 77s overall cycle |
| Morph amplitude | ±1.2% | Subtle |
| Lobes | 2 and 3 | Low frequency, integer |

## Trade-offs

- **Shadow doesn't follow morph** - Static path with large blur; ±1.2% morph is invisible
- **Highlight doesn't follow morph** - The `RadialGradient` center is fixed at `Alignment(-0.34, -0.42)`
- **77s cycle < Svelte's 154s** - Repeats sooner

## Tests

- Morph runs during animation and freezes when paused
- No frame-to-frame jumps across a full cycle (regression guard for Rules 1 & 2)
- Amplitude stays restrained (regression guard for Rule 3)

These tests catch the old buggy implementation: restoring the non-integer coefficients causes the frame-jump test to fail with 4.86px > 2.0px threshold.
