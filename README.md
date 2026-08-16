# ase-outline

An Aseprite outline that takes its colour from the art it touches, instead of
from a swatch. A white sleeve and dark armour on the same silhouette come out
with contours that belong to each of them.

Adds **Edit → FX → Colored Outline…**

## How the colour is picked

Every transparent pixel next to the shape looks at its neighbours and adopts
the colour of whichever one it mostly borders — orthogonal neighbours vote
twice, so a contour running along an edge keeps that edge's colour instead of
averaging into mud at every corner.

That colour is then shaded the way an artist picks a shadow by hand:

| Lever | What it does |
| --- | --- |
| **Shadow tint** | The hue everything drifts toward. Default is a cool violet-blue. |
| **Hue shift** | How far, in degrees, a colour may travel toward the tint. Capped rather than proportional: a plain fraction sends brown hair through magenta, because the short arc from warm to cool runs through pink. Neutrals have no hue to defend and adopt the tint outright — that is what turns grey armour blue-grey. |
| **Darken** | Value drop, applied per ring, so a thick outline keeps falling off. |
| **Saturate** | A little colour added, which is what stops the result reading as soot. |

Plus **Thickness** (1–4), **Corners** (`circle` = orthogonal only, `square` =
diagonals too), and **Snap to palette**.

## Where the result goes

A layer named `<layer> outline`, directly under the source, in the same group.
The original pixels are never touched, and the outline is free to sit outside
the old cel bounds. Re-running reuses that layer instead of stacking a new one
per attempt, so tuning the sliders does not leave a pile behind.

**Apply to** is a whole cel at a time — active cel, the layer across all
frames, or the timeline selection. That also means inner contours come for
free *only* when the parts are on separate layers: run it per-layer and an arm
gets outlined against the body. On a flattened sprite there is one silhouette,
so there is one outline.

## Colour modes

RGB is the honest case. Indexed art snaps to the existing palette whether or
not the option is on — there is nowhere else to put a colour — so the result is
only as good as the ramp already in the file, and it will happily reuse a
colour the art is using. Grayscale keeps the value drop and throws the hue away.

## Install

```bash
make install     # straight into the extensions folder; restart Aseprite
```

or build a double-clickable bundle:

```bash
make extension   # dist/ase-outline.aseprite-extension
```

## Tests

```bash
make test
```

Renders `out/before.png`, `out/after.png`, `out/after_thick.png` and
`out/indexed.png` for eyeballing, and asserts the parts that can be asserted:
cel geometry, layer order, the hue cap holding brown out of magenta, indexed
snapping never landing on the transparent index, and empty cels being refused
rather than crashed on.

## Status

v0.1.0, a prototype. Known gaps: no live preview in the dialog, and no
directional light — every side of the silhouette is shaded equally, where art
usually wants the contour lighter where the light hits and darker underneath.
