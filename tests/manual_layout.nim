## Interactive playground for the two-pen layout model
## (docs/layout_theory.md). Pick a stack direction (A2), a parent sizing
## mode (fixed region / hug / fill), tweak padding and spacing, and toggle
## the indent (T4) and centering (T5) demos. The colored boxes below
## respond to every change in real time, on the first frame, single pass.

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma, pixie,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont(
  "tests/data/IBMPlexSans-Regular.ttf",
  "Default",
  18.0,
  subpixelSteps = 10
)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "Layout Test",
  ivec2(900, 760),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  AreaBgColor = parseHtmlColor("#2a2a3e").rgbx
  Margin = 20.0f
  BoxColors = [
    parseHtmlColor("#e74c3c").rgbx,
    parseHtmlColor("#3498db").rgbx,
    parseHtmlColor("#2ecc71").rgbx,
    parseHtmlColor("#f39c12").rgbx,
    parseHtmlColor("#9b59b6").rgbx,
    parseHtmlColor("#1abc9c").rgbx,
    parseHtmlColor("#e67e22").rgbx,
    parseHtmlColor("#e84393").rgbx,
    parseHtmlColor("#00cec9").rgbx,
    parseHtmlColor("#6c5ce7").rgbx,
  ]
  BoxSizes = [
    vec2(48, 48),
    vec2(64, 32),
    vec2(32, 64),
    vec2(80, 40),
    vec2(40, 80),
    vec2(56, 56),
    vec2(72, 36),
    vec2(36, 72),
    vec2(60, 44),
    vec2(44, 60),
  ]
  Directions = [TopToBottom, BottomToTop, LeftToRight, RightToLeft]

let sk = newSilky(window, "tests/dist/atlas.png")

var
  layoutPadding = 12.0f
  layoutSpacing = 8.0f
  numBoxes = 5.0f
  directionVal = 0
  parentMode = 0 # 0 = fixed region, 1 = hug, 2 = fill cross axis
  showIndent = false
  showCenter = false
  showWidgets = false
  clickCount = 0

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  sk.at = vec2(Margin, Margin)
  h1text("Layout Test")

  scrubber("padding", layoutPadding, 0.0, 60.0, &"Padding: {layoutPadding:0.0f}")
  scrubber("spacing", layoutSpacing, 0.0, 40.0, &"Spacing: {layoutSpacing:0.0f}")
  scrubber("numBoxes", numBoxes, 1.0, 10.0, &"Boxes: {numBoxes.int}")

  ui:
    text("Stack direction (A2: pick the origin corner):")
    group "dirRow":
      hug()
      layout LeftToRight
      radioButton("Top to Bottom", directionVal, 0)
      radioButton("Bottom to Top", directionVal, 1)
      radioButton("Left to Right", directionVal, 2)
      radioButton("Right to Left", directionVal, 3)

    text("Parent sizing:")
    group "modeRow":
      hug()
      layout LeftToRight
      radioButton("Fixed region", parentMode, 0)
      radioButton("Hug children (T2)", parentMode, 1)
      radioButton("Fill cross axis (T3)", parentMode, 2)
      radioButton("Scroll frame (T7)", parentMode, 3)

    group "toggleRow":
      hug()
      layout LeftToRight
      checkBox("Indent (T4)", showIndent)
      checkBox("Centered box (T5)", showCenter)
      checkBox("Widgets in flow", showWidgets)

  let
    dir = Directions[directionVal]
    vertical = dir in [TopToBottom, BottomToTop]
    pad = layoutPadding
    spacing = layoutSpacing
    n = numBoxes.int
    areaTop = sk.at.y + 8
    areaPos = vec2(Margin, areaTop)
    areaSize = vec2(
      window.size.x.float32 - Margin * 2,
      window.size.y.float32 - areaTop - Margin
    )

  ui:
    rectangle "demoArea":
      box areaPos.x, areaPos.y, areaSize.x, areaSize.y
      tint AreaBgColor
      layout dir
      horizontalPadding pad
      verticalPadding pad
      itemSpacing spacing

      template demoBoxes() =
        for i in 0 ..< n:
          if showIndent and i >= 2 and i <= 3:
            indent 24:
              rectangle "box" & $i:
                size BoxSizes[i].x, BoxSizes[i].y
                tint BoxColors[i]
          else:
            rectangle "box" & $i:
              size BoxSizes[i].x, BoxSizes[i].y
              if parentMode == 2:
                # T3: stretch the cross axis into the known region.
                if vertical:
                  fillWidth()
                else:
                  fillHeight()
              tint BoxColors[i]
          if showWidgets and i == 1:
            button("Click " & $clickCount):
              inc clickCount
            checkBox("In flow", showWidgets)

      if parentMode == 1:
        # T2: the frame chrome is drawn behind children it hasn't seen
        # yet, sized by the stretch pen at close. With a reverse
        # direction this also exercises T6 (span translation).
        group "hugger":
          hug()
          patch "frame.9patch", 6
          layout dir
          horizontalPadding pad
          verticalPadding pad
          itemSpacing spacing
          demoBoxes()
      elif parentMode == 3:
        # T7: the scroll origin is the layout origin. A BottomToTop
        # frame rests scrolled to the bottom and its thumb rests at
        # the bottom of the track; RightToLeft rests at the right.
        frame "scroller":
          size 340, 300
          layout dir
          horizontalPadding pad
          verticalPadding pad
          itemSpacing spacing
          demoBoxes()
      else:
        demoBoxes()

      if showCenter:
        # T5: both parent and child known; does not advance the pen.
        rectangle "centered":
          size 120, 60
          center()
          tint rgbx(255, 255, 255, 40)
          patch "frame.9patch", 6
          text "centerLabel":
            characters "centered"

  # Frame time.
  sk.at = vec2(sk.size.x - 250, Margin)
  let ms = sk.avgFrameTime * 1000
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
