## Demonstrates low-level raw triangle drawing.

import
  std/[strformat],
  windy, bumpy, vmath, chroma,
  silky

when not defined(useDirectX):
  import opengl

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/atlas.png")

let window = newWindow(
  "Geometry Example",
  ivec2(900, 700),
  vsync = false
)
makeContextCurrent(window)
when not defined(useDirectX):
  loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  PanelColor = parseHtmlColor("#2a2a3e").rgbx
  Margin = 24.0f

let sk = newSilky(window, "tests/dist/atlas.png")

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    text "title":
      box Margin, Margin, 500, 40
      characters "Manual Geometry"
      font "H1"
      tint sk.theme.textH1Color

    text "blurb":
      box Margin, 72, 700, 30
      characters "The triangle below uses raw positions, UVs, and per-vertex colors."

    let
      panelPos = vec2(120, 160)
      panelSize = vec2(660, 420)
      tri = [
        vec2(450, 200),
        vec2(260, 500),
        vec2(640, 500)
      ]
      uv = [
        vec2(8, 8),
        vec2(8, 8),
        vec2(8, 8)
      ]
      colors = [
        rgbx(255, 90, 90, 255),
        rgbx(90, 255, 160, 255),
        rgbx(90, 140, 255, 255)
      ]

    sk.drawRect(panelPos, panelSize, PanelColor)
    sk.drawTriangle(tri, uv, colors)

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, Margin, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
