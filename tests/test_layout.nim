## Headless tests for the two-pen layout model (docs/layout_theory.md).
## Asserts exact rects for all four stack directions (T1), hug (T2),
## fill (T3), indent (T4), centering (T5), and reverse-direction hug
## (T6) via the semantic capture layer.
## Run with: nim r -d:silkyTesting tests/test_layout.nim

when not defined(silkyTesting):
  {.error: "Must compile with -d:silkyTesting".}

import
  std/unittest,
  bumpy, vmath,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/test_layout_atlas.png")

# The demo region: box at (50, 50) sized 400x300, padding 10, spacing 5.
# Inner region: pos (60, 60), size (380, 280).
# Two boxes: b0 48x48, b1 64x32.
var
  dir = TopToBottom
  hugMode = false
  fillCross = false
  indentSecond = false
  centered = false
  scrollFrame = false

proc layoutUI(sk: Silky, window: Window) =
  ui:
    rectangle "demoArea":
      box 50, 50, 400, 300
      tint "#2a2a3e"
      layout dir
      horizontalPadding 10
      verticalPadding 10
      itemSpacing 5

      template boxes() =
        rectangle "b0":
          size 48, 48
          if fillCross:
            fillWidth()
          tint "#e74c3c"
        if indentSecond:
          indent 24:
            rectangle "b1":
              size 64, 32
              tint "#3498db"
        else:
          rectangle "b1":
            size 64, 32
            tint "#3498db"

      if hugMode:
        group "hugger":
          hug()
          layout dir
          horizontalPadding 10
          verticalPadding 10
          itemSpacing 5
          boxes()
      else:
        boxes()

      if centered:
        rectangle "c":
          size 120, 60
          center()
          tint "#ffffff"

    if scrollFrame:
      # T7: frame at (450, 0) sized 200x150, default padding 8.
      # Inner region: (458, 8) size 184x134; bottom edge y = 142.
      frame "sf":
        box 450, 0, 200, 150
        layout dir
        for i in 0 ..< 8:
          rectangle "sb" & $i:
            size 40, 40
            tint "#2ecc71"

proc rectOf(h: TestHarness, name: string): Rect =
  let node = h.sk.semantic.root.findByName(name, "Rectangle")
  check node != nil
  if node != nil:
    result = node.rect

proc hugRectOf(h: TestHarness, name: string): Rect =
  let node = h.sk.semantic.root.findByName(name, "Group")
  check node != nil
  if node != nil:
    result = node.rect

proc checkRect(r: Rect, x, y, w, h: float32) =
  check abs(r.x - x) < 0.5
  check abs(r.y - y) < 0.5
  check abs(r.w - w) < 0.5
  check abs(r.h - h) < 0.5

var h = newTestHarness("tests/dist/test_layout_atlas.png", 800, 600)

proc pump() =
  discard h.pumpFrame(layoutUI)

suite "Two-pen layout":

  setup:
    dir = TopToBottom
    hugMode = false
    fillCross = false
    indentSecond = false
    centered = false
    scrollFrame = false
    if frameStates.contains("sf"):
      frameStates["sf"].scrollPos = vec2(0, 0)

  test "T1 TopToBottom: pen walks down from the top-left":
    pump()
    checkRect(h.rectOf("b0"), 60, 60, 48, 48)
    checkRect(h.rectOf("b1"), 60, 113, 64, 32)

  test "T1 BottomToTop: pen walks up from the bottom-left":
    dir = BottomToTop
    pump()
    # Inner bottom edge is y = 340; b0 sits on it (A3: stretches away).
    checkRect(h.rectOf("b0"), 60, 292, 48, 48)
    checkRect(h.rectOf("b1"), 60, 255, 64, 32)

  test "T1 LeftToRight: pen walks right from the top-left":
    dir = LeftToRight
    pump()
    checkRect(h.rectOf("b0"), 60, 60, 48, 48)
    checkRect(h.rectOf("b1"), 113, 60, 64, 32)

  test "T1 RightToLeft: pen walks left from the top-right":
    dir = RightToLeft
    pump()
    # Inner right edge is x = 440; b0's right edge sits on it.
    checkRect(h.rectOf("b0"), 392, 60, 48, 48)
    checkRect(h.rectOf("b1"), 323, 60, 64, 32)

  test "T2 hug: parent sizes to children extent + padding":
    hugMode = true
    pump()
    # extent = (max(48, 64), 48 + 5 + 32) = (64, 85); + padding 20.
    checkRect(h.hugRectOf("hugger"), 60, 60, 84, 105)
    checkRect(h.rectOf("b0"), 70, 70, 48, 48)
    checkRect(h.rectOf("b1"), 70, 123, 64, 32)

  test "T6 reverse hug: same size, anchored to the bottom":
    hugMode = true
    dir = BottomToTop
    pump()
    # Same hug size; its bottom edge sits on the inner bottom (340).
    checkRect(h.hugRectOf("hugger"), 60, 235, 84, 105)

  test "T3 fill: child takes the known inner cross size":
    fillCross = true
    pump()
    checkRect(h.rectOf("b0"), 60, 60, 380, 48)

  test "T4 indent: cross-axis nudge for the indented block":
    indentSecond = true
    pump()
    checkRect(h.rectOf("b0"), 60, 60, 48, 48)
    checkRect(h.rectOf("b1"), 84, 113, 64, 32)

  test "T5 center: both known, centered in the inner region":
    centered = true
    pump()
    checkRect(h.rectOf("c"), 190, 170, 120, 60)

  test "T5 center: does not advance the pen":
    centered = true
    pump()
    # b1 is placed exactly as without the centered box.
    checkRect(h.rectOf("b1"), 60, 113, 64, 32)

  test "T7 scroll: top-origin frame rests at the top":
    scrollFrame = true
    pump()
    checkRect(h.rectOf("sb0"), 458, 8, 40, 40)

  test "T7 scroll: bottom-origin frame rests scrolled to the bottom":
    scrollFrame = true
    dir = BottomToTop
    pump()
    # First box sits on the inner bottom edge — origin pinned at rest.
    checkRect(h.rectOf("sb0"), 458, 102, 40, 40)

  test "T7 scroll: t translates content by -sigma*t":
    scrollFrame = true
    dir = BottomToTop
    pump()
    frameStates["sf"].scrollPos = vec2(0, 30)
    pump()
    # Content moves down 30 px, revealing the overflow hiding above.
    checkRect(h.rectOf("sb0"), 458, 132, 40, 40)

  test "T7 scroll: t clamps to the overflow":
    scrollFrame = true
    dir = BottomToTop
    pump()
    frameStates["sf"].scrollPos = vec2(0, 99999)
    pump()
    pump()
    # Content = 8 * (40 + 8) + 16 = 400; overflow = 400 - 150 = 250.
    check abs(frameStates["sf"].scrollPos.y - 250) < 0.5

echo "All layout tests done."
