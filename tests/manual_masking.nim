## Manual test for drawImage with mask support.

import
  windy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "Masking Test",
  ivec2(600, 400),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "tests/dist/atlas.png")

let tintColor = rgbx(255, 80, 80, 255)

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(rgbx(40, 40, 40, 255))

  const
    Left = 20.0f
    LabelX = 70.0f
    Spacing = 50.0f
    LabelW = 400.0f
    LabelH = 24.0f

  ui:
    sk.drawImage("heart", vec2(Left, 20))
    text "base label":
      box LabelX, 26, LabelW, LabelH
      characters "Base image (no mask, no tint)"

    sk.drawImage("heart.mask", vec2(Left, 20 + Spacing))
    text "mask label":
      box LabelX, 26 + Spacing, LabelW, LabelH
      characters "Mask image"

    sk.drawImage("heart", vec2(Left, 20 + Spacing * 2), tintColor, "heart.mask")
    text "masked label":
      box LabelX, 26 + Spacing * 2, LabelW, LabelH
      characters "Masked + tinted"

    sk.drawImage("heart", vec2(Left, 20 + Spacing * 3), tintColor)
    text "tinted label":
      box LabelX, 26 + Spacing * 3, LabelW, LabelH
      characters "Tinted without mask"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
