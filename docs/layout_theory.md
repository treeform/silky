# A Theory of Immediate-Mode Layout

Layout needs no tree, no measure pass, and no cache. It needs exactly two
points of state — two pens — and a handful of axioms about how they move.
Everything else (stack directions, hug, fill, indent, centering,
scrolling) is a theorem derived from them.

## The two pens

- **The pen** `P` — where the next element is drawn.
- **The stretch pen** `S` — the farthest corner any element has reached.

That is the entire layout state of a scope. If a layout idea cannot be
expressed as motion of these two pens, it is not silky-immediate-mode and we do
not build it.

```
O...................       O = origin corner: both pens start here
: +-------------+  :
: |  first      |  :
: +-------------+  :
: +-------+        :
: | second|        :
: +-------+        :
: P                :       P = pen: the next element draws here
:..................S       S = stretch pen: farthest corner reached
                           box(O,S) = the content box, at all times
```

## Axioms

**A1 — State.** A layout scope carries two points, the pen `P` and the
stretch pen `S`, and a sign vector `σ = (σx, σy)`, each component `+1` or
`-1`. Nothing else is remembered between elements.

**A2 — Origin.** A scope begins at an *origin corner* `O`: any of the
four corners of its region (moved inward by padding). Both pens start
there: `P = S = O`. The choice of corner is exactly the choice of `σ` —
`σ` points from the origin corner into the region. The stack direction
picks which axis of `σ` is the *main* axis; the other is the *cross*
axis. Four directions × two cross signs = the four corners: you can
start anywhere and go any way.

```
TopToBottom       BottomToTop       LeftToRight       RightToLeft
(origin: top)     (origin: bottom)  (origin: left)    (origin: right)

O---------+       +---------+       O---------+       +---------O
| [1]     |       | [3]     |       |[1][2][3]|       |[3][2][1]|
| [2]     |       | [2]  ^  |       |      -> |       | <-      |
| [3]  |  |       | [1]  |  |       |         |       |         |
+------v--+       O---------+       +---------+       +---------+

[n] = draw order.  The pen starts at O and advances along the arrow.
```

**A3 — Draw.** An element of size `s` drawn at pen `P` occupies the box
spanning from `P` to `P + σ·s` (componentwise). An element is drawn where
the pen is, and stretches the other way — always away from the origin
corner, never toward it.

```
σ = (+1,+1)                        σ = (-1,-1)
element grows right + down:        element grows left + up:

P-----------+                      +-----------+
|  element  |                      |  element  |
|           v                      ^           |
+---------->+                      +<----------P
```

**A4 — Advance.** After an element is drawn, the pen moves along the main
axis only:

```
P.main += σ.main · (s.main + spacing)
```

`P.cross` never moves on its own.

**A5 — Stretch.** After an element is drawn, the stretch pen absorbs its
far corner, componentwise in the direction of `σ`:

```
S = farthest_σ(S, P_before + σ·s)
```

The stretch pen only ever moves away from the origin. `box(O, S)` is at
every moment the exact bounding box of everything drawn so far — the
*content box*.

**A6 — Relativity.** Everything inside a scope is positioned relative to
its origin `O`. A finished scope is a rigid box `box(O, S)`; drawing
commutes with translation, so the parent may place that box anywhere and
the contents move with it.

**A7 — Composition.** A child scope opens with its origin at the parent's
pen (its `σ` is its own). When it closes, its content box becomes an
ordinary element of size `|S − O|` in the parent, subject to A3, A4, A5.
Layout is this recursion and nothing more.

**A8 — Knowledge.** A length is *known* if it was given (fixed), measured
(text, image), or inherited from a known region. A scope's own extent is
known only when it closes. Any rule that consumes a length may only
consume a known one; there is no way to ask about the future.

## The axioms in one picture

```
Vertical layout parent (TopToBottom, origin top-left)

+- parent ------------------------------------+
|                                             |   padding moves O
|<-pad-> O                            <-pad-> |   inward (A2)
|        +- child 1 ---------------+          |
|        |                         |          |   child advance: after
|        +-------------------------+          |   drawing, P moves down by
|        :  item spacing                      |   s.main + spacing (A4)
|        +- child 2 ---------------+          |
|        |<----- child stretch ----|--------->|   child stretch: take the
|        +-------------------------+          |   parent's known inner
|        P                         .          |   width on the cross
|        |                         .          |   axis (T3)
|        v                         S          |
+---------------------------------------------+

Horizontal layout parent (LeftToRight, origin top-left)

+- parent ------------------------------------+
|                                             |
|        O           :item                    |
|        +- child 1 -+:spacing +- child 2 -+  |
|        |           |         |           |  |
|        |           |         |           | ->  P advances right (A4)
|        +-----------+         +-----------+  |
|                                          S  |
+---------------------------------------------+
```

**T1 — The four directions are one rule.** No per-direction cases exist:
flipping `σ` components in A3–A5 produces all of them. (The failed
`layout` branch was an attempt to write A3–A5 pointwise as 4×4 sign
tables — every combination hand-derived, every new feature multiplying
the cases.)

**T2 — Hug.** When a scope closes, `box(O, S)` is its size (A5), and by
A7 the parent consumes it like any fixed element. A parent hugs its
children by definition — no measuring pass, because the stretch pen was
measuring all along. Drawing the parent's own chrome *behind* children it
hasn't seen yet is an implementation concern (reserved vertex span), not
a theoretical one: by A6 the chrome is just part of the rigid box.

**T3 — Fill.** If a scope's region length `R` is known (A8), the
remaining space along an axis is `R − |P − O|`, available right now, and
an element may take it as its size. Fill inside an unknown (hug) region
is *undefined by A8*, not unsupported: the space does not exist yet, and
no pass will come along later to invent it.

```
Fixed: you say it     Hug: children say it     Fill: parent says it
                      (T2)                     (parent must be known)

+---- 240px ----+     O...............        +- parent known -----+
|               |     : [child]      :        | +----------------+ |
|               |     : [wider child]:        | |<---- fill ---->| |
+---------------+     :..............S        | +----------------+ |
                      parent becomes          | child takes what   |
                      box(O,S) + padding      | remains, right now |
                                              +--------------------+
```

**T4 — Indent.** `P.cross += σ.cross · n` (and its inverse to de-indent).
Legal because A4 reserves cross-axis motion for exactly this kind of
explicit nudge; persistent for following siblings because A4 never
touches cross; safe because the stretch pen (A5) keeps recording the
truth about extent.

```
O
+--------------------------------------+
| [########## row 1 ###########]       |
|     [###### row 2 ######]            |   indent
|         [## row 3 ##]                |   indent again
|         [#### row 4 ########]        |   (cross offset persists, A4)
|     [##### row 5 #####]              |   de-indent
+--------------------------------------+
      the pen walks down the main axis; indent nudges where
      each row begins on the cross axis
```

**T5 — Centering.** By A8 centering consumes two lengths — the region's
and the element's — so both must be known; then `P = center − s/2` is
plain arithmetic, a degenerate scope with no advance. "Centering only
when both sizes are known" is a consequence of the axioms, not a caveat.

```
+- parent: size known ------------+
|                .                |
|        +-- child: known --+     |
| . . . .|         +        |. . .|   center X
|        +------------------+     |
|                .                |
|                . center Y       |
+---------------------------------+

P = center - s/2 on each centered axis; both lengths
must already be known (A8)
```

**T6 — Reverse-direction hug.** A child whose extent is unknown (A8)
inside a reverse-direction parent seems paradoxical: A3 wants to place
its box against the pen, but the box's size arrives only at close. A6
resolves it: contents are drawn relative to `O`, the finished box is
rigid, so placement may happen *at close* and the whole box translates
into position. (Implementation: shift the vertex span; theory: position
was never absolute to begin with.)

**T7 — Scrolling.** Scrolling is not a widget; it is the natural
ramification of clipping children inside a parent. If a scope clips to a
known region `R` and its content box outgrows it, the overflow is

```
V = max(|S − O| − R, 0)        (per axis)
```

A scroll offset `t ∈ [0, V]` translates the contents by `−σ·t` (legal by
A6; the clip stays on the region). Because content can only ever grow
*away* from the origin corner (A3, A5), everything about scrolling is
already decided:

- **The scroll origin is the layout origin.** At rest (`t = 0`) the
  origin edge is pinned and visible; the overflow hides at the far end.
  A bottom-origin stack rests scrolled to the bottom and scrolls up. A
  right-origin stack rests at the right and scrolls left. A top-origin
  stack rests at the top — the familiar case, revealed as just one of
  four.
- **The scrollbar starts where the layout starts.** The thumb sits at
  the origin edge of the track at `t = 0` and moves away from it; its
  length is the visible fraction `R / |S − O|`. The scrollbar is nothing
  but the visible ratio of the two pens' separation to the region.
- **Origin-pinning falls out.** Content added to a bottom-origin log
  while resting at `t = 0` keeps the origin edge pinned — chat-style
  follow behavior with no special case.

```
Top-origin (TopToBottom)           Bottom-origin (BottomToTop)
rest shows the top:                rest shows the bottom:

O--------------+-+                 . [5]          .    overflow hides
| [1]          |#|  thumb rests    . [4]..........:    past the far
| [2]          |#|  at the origin  +--------------+-+  (top) edge
| [3]          | |  (top), moves   | [3]          | |
+--------------+-+  away from it   | [2]          |#|  thumb rests at
. [4]          .                   | [1]          |#|  the origin
. [5]..........:    overflow past  O--------------+-+  (bottom), moves
                    the far edge                       up as you scroll

[n] = draw order. Dotted = clipped content, # = scrollbar thumb.
```

The offset `t` persists across frames, but it is user interaction state
(like a checkbox's bool), not derived layout — the content size it is
clamped against is re-measured from the pens every frame. Works
identically in all four directions because A5 does.

**T8 — Completeness (informal).** Fixed, fill, and hug per axis; four
origins; indent on the cross axis; nesting by A7 — this closes over the
layouts in the diagrams: stacks in any direction with anchoring, parents
hugging children or children filling parents, indentation trees, centered
dialogs, scrolling frames. Anything expressible as pens flowing corner to
corner is drawable in a single pass on the first frame.

## What the axioms forbid

These are not missing features; they contradict A8 (no knowledge of the
future) and are what make the single pass possible:

- Fill or stretch inside a hug region (T3).
- Centering against an unknown size (T5).
- Weighted multi-fill (flexbox `flex-grow` ratios) — dividing remaining
  space among elements requires seeing all of them first: a second pass.
- Justify/space-between — same reason.

Each gets a predictable degradation (fall back to content size) and a
debug-build warning.

## Correspondence to today's code

The pens already exist: `sk.at` is `P`, `sk.stretchAt` is `S`
(`contexts.nim`). But today `stretchAt` is forward-biased (`max` only) —
A5 says it must move *in the direction of σ* — and `advance` plus
`pushLayout` hard-code fragments of A3–A5 per direction at call sites.
The implementation plan (`layout_plan.md`) is the mechanical work of
making the code satisfy the axioms: one `place()` owning A3–A5, an
origin+signs scope owning A2, spans owning A6.
