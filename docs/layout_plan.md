# Immediate-Mode Layout — Implementation Plan

This plan realizes the axioms in [layout_theory.md](layout_theory.md).
Read that first; nothing here introduces a concept the theory doesn't.
The job is to make the code satisfy the axioms: today `sk.at` and
`sk.stretchAt` are the two pens (A1), but the axioms around them are
enforced nowhere in particular — direction math is smeared across
`pushLayout`, `advance`, `inferNodeSize`, and the DSL.

## Why the previous attempt (`layout` branch) stalled

`manual_layout3.nim` treated *direction* and *anchor* as independent
4-way choices, forcing a 4×4 table of hand-tuned sign vectors
(`mainDirs`, `paddingDirs`, `sizeSign`) with sign-sensitive
`stretchMin`/`stretchMax` updates at every step. That is axioms A3–A5
written out pointwise, one combination at a time. The theory collapses
it: the anchor *is* the origin corner, the origin corner *is* the sign
vector `σ` (A2), and one `place()` function applies A3–A5 for every
direction at once (T1).

## The key implementation enabler: the vertex buffer is patchable

The drawer keeps plain CPU-side `seq[DrawerVertex]` per layer
(`drawers/ogl.nim`), uploaded once at frame end, and each vertex is
self-contained (pos, uv, color, clipPos/clipSize, maskUv). This is what
lets axiom A6 (relativity — a finished scope is a rigid, placeable box)
be realized within a single frame:

1. **Reserve** a vertex span before children draw, **fill it in** at
   scope close → a hug parent draws behind children it hadn't seen yet
   (T2).
2. **Translate** an emitted span (pos and clipPos) at scope close →
   deferred placement of unknown-size boxes (T6).

Both are O(1)-per-vertex writes into slots already allocated this frame —
no cache, no retained tree.

## Sizing modes (A8 in code)

Per-axis mode on each node:

| Mode | Known at... | Meaning |
|---|---|---|
| `Fixed` | begin | explicit px, or measured content (text, image) |
| `Fill` | begin, iff parent axis known | remaining region space (T3) |
| `Hug` | close | content box `|S − O|` (T2) |

Legality follows T3/T5: Fill or centering inside an unknown axis
degrades to content size with a debug-build warning.

## The layout scope

Today's four parallel stacks (`atStack`, `posStack`, `sizeStack`,
`directionStack`) plus the single global `stretchAt` become one stack of
scopes — a scope is the theory's tuple `(O, σ, P, S)` plus bookkeeping:

```nim
LayoutScope = object
  origin: Vec2           # O — the anchor corner, padded inward (A2)
  signs: Vec2            # σ — (+1|-1) per axis (A2)
  mainAxis: int          # 0 = x, 1 = y (from the stack direction)
  regionSize: Vec2       # 0 where unknown
  knownW, knownH: bool   # A8
  pen: Vec2              # P (A1)
  stretch: Vec2          # S (A1); starts at origin, moves only along σ
  itemSpacing: float32
  indent: float32        # cross-axis pen offset (T4)
  spanStart: (int, int)  # (layer, vertexIndex) at open — for A6 patch/shift
  placedCount: int       # spacing goes between elements, not before the first
```

Exactly two procs own the axioms — no other code moves a pen:

```nim
proc place(scope: var LayoutScope, size: Vec2): Vec2
  ## A3 + A4 + A5 in one motion, valid for all four σ:
  ## returns the element's min corner (box spans pen → pen + σ·size),
  ## advances pen along main axis by σ·(size + spacing),
  ## absorbs the far corner into stretch.

proc contentBox(scope: LayoutScope): Rect
  ## box(O, S) — what a hug parent becomes (T2), what scrollbars
  ## measure (T7).
```

`pushLayout`/`popLayout`/`advance`/`pos`/`size` remain as thin
compatibility wrappers over the scope stack.

## Feature-by-feature realization

- **Four directions (T1).** `resolveNodeRect`/`inferNodeSize` route
  through `place()`; the per-direction `case` blocks in `advance` and
  `pushLayout` are deleted, replaced by `σ`.
- **Hug (T2).** At node begin: reserve chrome span (9-patch = 9 quads =
  54 verts, rect = 6). Children emit normally. At close: rect =
  `contentBox()` + padding, patch the span, then the parent consumes the
  size via its own `place()`.
- **Fill (T3).** Remaining space `R − |P − O|` along a known axis;
  cross-axis stretch = known inner cross size. Unknown parent axis →
  content fallback + debug warning.
- **Indent (T4).** `indent(n)` / block template adjusts `scope.indent`;
  `place()` adds `σ.cross · indent` on the cross axis.
- **Centering (T5).** `center()` legal when both region and element are
  known; pure arithmetic at placement, no advance.
- **Reverse-direction hug (T6).** Child laid out relative to provisional
  origin; at close, `translateSpan` shifts its vertices (pos + clipPos)
  into final position and the pen is corrected. Nodes that shifted
  re-resolve their interaction rect at close.
- **Scrolling (T7).** `finishFrameScrollbars` measures `contentBox()`
  instead of forward-only `stretchAt`, and `FrameState.scrollPos`
  becomes `t`: distance from the origin corner, per axis, clamped to
  the overflow — not a top-left-biased pixel offset. The child scope's
  origin is translated by `−σ·t`. Thumb position and travel direction
  derive from `σ`: the thumb rests at the origin edge of the track
  (bottom-origin frame → thumb starts at the bottom, scrolls up;
  right-origin → starts right, scrolls left). Mouse-wheel sign maps to
  `dt` per axis via `σ` so wheel-down always reveals the far end.
- **Interaction on hug nodes.** `onClick`/`onHover` resolve the rect at
  the moment they're called, i.e. against the content box *so far*.
  Documented rule: event handlers go after the children in the body
  (natural for buttons: content first, `onClick` last). No frame lag,
  no rect cache.

## API sketch (DSL additions)

```nim
group "toolbar":
  layout LeftToRight
  hug()                  # both axes; or hugWidth()/hugHeight()
  itemSpacing 4
  ...

frame "sidebar":
  width 240              # Fixed main axis
  fillHeight()           # Fill cross axis
  ...

rectangle "badge":
  size 60, 20
  center()               # T5: both known, else debug warning

group "tree":
  indent 16:             # T4
    text "child": ...

rectangle "log":
  size 400, 200
  scrollable()           # T7: independent of sizing — scrolling is a
  ...                    # ramification of clipping, legal on any
```                      # known-size node (not hug, A8)

Defaults stay compatible: `frame`/`group` keep today's
fill-remaining-space behavior unless told otherwise; `text`/`image` stay
content-measured.

## Phases

**Phase 1 — make the pens lawful (no visible behavior change)**
1. `LayoutScope` replaces the parallel stacks and global `stretchAt`;
   `place()`/`contentBox()` own A3–A5; wrappers keep the old API.
2. Drawer span API: `reserveQuads(count) -> Span`, patching via a common
   quad emitter shared with `drawRect`/`draw9Patch`, and
   `translateSpan(span, offset)`.
3. Existing examples/tests must not move by a pixel (TopToBottom and
   LeftToRight parity).

**Phase 2 — sizing modes**
4. Per-axis `SizeMode` on `DslNode`; `width`/`height`/`size`/`fill*`/
   `hug*` verbs; known-flag propagation; debug-build legality warnings.
5. Hug via reserved chrome span (T2).
6. Route DSL rect resolution through `place()` — fixes reverse
   directions for known-size children immediately (T1).
7. `center()` (T5).

**Phase 3 — the long tail**
8. `indent` block template (T4).
9. Reverse-direction hug via `translateSpan` + interaction re-resolve
   (T6).
10. Scrollbar content from `contentBox()` (T7).

**Phase 4 — proof**
11. `examples/layouts` becomes the interactive playground the old branch
    wanted: scrubbers for padding/spacing/box count, radios for the four
    directions and origin corners, toggles for hug/fill/fixed — every
    diagram reproduced live.
12. Golden tests via the `silkyTesting` harness: 4 directions ×
    {fixed, fill, hug} parents, nested hug, indent, centering, and a
    BottomToTop scrolling frame.

## Deliberately not built

Per the theory's "what the axioms forbid" (violations of A8): fill or
centering inside hug, weighted multi-fill (`flex-grow`), and
justify/space-between — each requires seeing all siblings before placing
the first, i.e. a second pass. Degradation is predictable (content size)
and warned in debug builds.
