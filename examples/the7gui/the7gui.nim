
import
  std/[strformat, strutils],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png", "dist/atlas.json")

let window = newWindow(
  "7GUIs - Counter",
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
  showCounter = true
  showTemperature = true
  counter = 0
  celsius = "0"
  fahrenheit = "32"

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  subWindow("Counter", showCounter):
    text(&"{counter}")
    button("Count"):
      inc counter

  subWindow("Temperature Converter", showTemperature):
    let oldCelsius = celsius
    text("Celsius")
    inputText(1, celsius)
    if celsius != oldCelsius:
      try:
        let c = parseFloat(celsius)
        let f = c * (9.0 / 5.0) + 32.0
        fahrenheit = fmt"{f:.1f}"
        if 2 in textInputStates:
           textInputStates[2].setText(fahrenheit)
      except ValueError:
        discard

    let oldFahrenheit = fahrenheit
    text("Fahrenheit")
    inputText(2, fahrenheit)
    if fahrenheit != oldFahrenheit:
      try:
        let f = parseFloat(fahrenheit)
        let c = (f - 32.0) * (5.0 / 9.0)
        celsius = fmt"{c:.1f}"
        if 1 in textInputStates:
           textInputStates[1].setText(celsius)
      except ValueError:
        discard

  if not showCounter and not showTemperature:
    if window.buttonPressed[MouseLeft]:
      showCounter = true
      showTemperature = true
    sk.at = vec2(100, 100)
    text("Click anywhere to show the windows")

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
