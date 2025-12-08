
import 
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
  silky

var builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png", "dist/atlas.json")

var window = newWindow(
  "Basic Menu", 
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#000000").rgbx

var sk = newSilky("dist/atlas.png", "dist/atlas.json")

var 
  showWindow = true

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  windowFrame("A Window", showWindow):  
    text("Hello world!")
    button("Close Me"):
      showWindow = false

  if window.buttonPressed[KeySpace]:
    showWindow = not showWindow

 
  let ms = sk.avgFrameTime * 1000
  sk.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
