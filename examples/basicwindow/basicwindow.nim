
import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png", "dist/atlas.json")

let window = newWindow(
  "Basic Window",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#000000").rgbx

let sk = newSilky("dist/atlas.png", "dist/atlas.json")

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

var
  showWindow = true
  inputText = "Type here!"
  option = 1
  cumulative = false

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  subWindow("A SubWindow", showWindow):
    text("Hello world!")
    button("Close Me"):
      showWindow = false
    inputText(10, inputText)

    radioButton("Avg", option, 1)
    radioButton("Max", option, 2)
    radioButton("Min", option, 3)

    checkBox("Cumulative", cumulative)

    text("A bunch of text to test the scrolling, in any direction.")
    text("Does it work?")

    for i in 0 ..< 10:
      text("Time will tell...")

  if not showWindow:
    if window.buttonPressed[MouseLeft]:
      showWindow = true
    sk.at = vec2(100, 100)
    text("Click anywhere to show the window")

  let ms = sk.avgFrameTime * 1000
  sk.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
