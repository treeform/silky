## Manual test for draw9Patch with adjustable border sliders.

import
  std/[strformat],
  opengl, windy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "9-Patch Test",
  ivec2(900, 700),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "tests/dist/atlas.png")

var
  use4Patch = false
  patchTop = 8.0f
  patchRight = 20.0f
  patchBottom = 16.0f
  patchLeft = 4.0f
  drawWidth = 300.0f
  drawHeight = 200.0f

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(rgbx(40, 40, 40, 255))

  const
    Margin = 20.0f
    LabelWidth = 80.0f
    SliderWidth = 300.0f

  ui:
    text "title":
      box Margin, Margin, 400, 24
      characters "9-Patch Manual Test"

    let refX = Margin + LabelWidth + SliderWidth + Margin
    text "original label":
      box refX, 55, 200, 24
      characters "Original:"
    sk.drawImage("debug.9patch", vec2(refX, 80))

    group "controls":
      box Margin, 55, LabelWidth + SliderWidth, 280
      layout TopToBottom
      itemSpacing 12
      checkBox "4-patch (independent borders)", use4Patch

      group "width row":
        box LabelWidth + SliderWidth, 24
        layout LeftToRight
        text "width label":
          box LabelWidth, 24
          characters "Width:"
        group "width slider":
          box SliderWidth, 24
          scrubber("width", drawWidth, 32.0, 600.0, &"{drawWidth:.0f}")

      group "height row":
        box LabelWidth + SliderWidth, 24
        layout LeftToRight
        text "height label":
          box LabelWidth, 24
          characters "Height:"
        group "height slider":
          box SliderWidth, 24
          scrubber("height", drawHeight, 32.0, 600.0, &"{drawHeight:.0f}")

      if use4Patch:
        group "top row":
          box LabelWidth + SliderWidth, 24
          layout LeftToRight
          text "top label":
            box LabelWidth, 24
            characters "Top:"
          group "top slider":
            box SliderWidth, 24
            scrubber("top", patchTop, 0.0, 32.0, &"{patchTop:.0f}")

        group "right row":
          box LabelWidth + SliderWidth, 24
          layout LeftToRight
          text "right label":
            box LabelWidth, 24
            characters "Right:"
          group "right slider":
            box SliderWidth, 24
            scrubber("right", patchRight, 0.0, 32.0, &"{patchRight:.0f}")

        group "bottom row":
          box LabelWidth + SliderWidth, 24
          layout LeftToRight
          text "bottom label":
            box LabelWidth, 24
            characters "Bottom:"
          group "bottom slider":
            box SliderWidth, 24
            scrubber("bottom", patchBottom, 0.0, 32.0, &"{patchBottom:.0f}")

        group "left row":
          box LabelWidth + SliderWidth, 24
          layout LeftToRight
          text "left label":
            box LabelWidth, 24
            characters "Left:"
          group "left slider":
            box SliderWidth, 24
            scrubber("left", patchLeft, 0.0, 32.0, &"{patchLeft:.0f}")
      else:
        group "patch row":
          box LabelWidth + SliderWidth, 24
          layout LeftToRight
          text "patch label":
            box LabelWidth, 24
            characters "Patch:"
          group "patch slider":
            box SliderWidth, 24
            scrubber("patch", patchTop, 0.0, 32.0, &"{patchTop:.0f}")

    # Draw the 9-patch below the controls.
    let
      drawPos = vec2(Margin, 360)
      drawSize = vec2(drawWidth, drawHeight)

    if use4Patch:
      sk.draw9Patch(
        "debug.9patch",
        patchTop.int,
        patchRight.int,
        patchBottom.int,
        patchLeft.int,
        drawPos,
        drawSize
      )
    else:
      sk.draw9Patch("debug.9patch", patchTop.int, drawPos, drawSize)

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
