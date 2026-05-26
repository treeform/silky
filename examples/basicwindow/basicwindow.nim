import
  std/[strformat],
  bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "Basic Window",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "dist/atlas.png")

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

var
  showWindow = true
  inputText = "Type here!"
  option = 1
  cumulative = false
  element = "Fire"
  power = "Medium"
  progress = 0.0
  howMuch = 30.0
  earlyReturn = true

proc returnTest() =
  text "return title":
    characters "Return Test"
  group "return row":
    box 220, 34
    layout LeftToRight
    itemSpacing 8
    text "return group":
      characters "Group"
    if earlyReturn:
      return
  text "return hidden":
    characters "You will not see this."

window.onFrame = proc() =
  if window.buttonPressed[KeyEqual] or
    window.buttonPressed[NumpadAdd]:
    sk.uiScale = min(sk.uiScale + 0.25'f, 4.0'f)
  if window.buttonPressed[KeyMinus] or
    window.buttonPressed[NumpadSubtract]:
    sk.uiScale = max(sk.uiScale - 0.25'f, 0.25'f)

  sk.beginUI(window, window.size)

  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.drawImage("testTexture", vec2(x.float32 * 256, y.float32 * 256), rgbx(30, 30, 30, 255))

  ui:
    subWindow("A SubWindow", showWindow, vec2(100, 100), vec2(400, 700)):
      text "hello":
        characters "Hello world!"

      button "Close Me":
        showWindow = false

      textInput "input", inputText

      group "radio buttons":
        box 350, 32
        layout LeftToRight
        itemSpacing 12
        radioButton "Avg", option, 1
        radioButton "Max", option, 2
        radioButton "Min", option, 3

      checkBox "Cumulative", cumulative

      text "select label":
        characters "Select an option:"
      dropDown element, ["Fire", "Water", "Earth", "Air"]
      dropDown power, ["Low", "Medium", "High"]

      text "progress label":
        characters "Progress Bar:"
      progressBar progress, 0, 100
      progress += 0.01
      if progress > 100.0:
        progress = 0.0

      text "scrubber label":
        characters &"How much: {howMuch:.2f}"
      scrubber "howMuch", howMuch, 0.0, 100.0, &"{howMuch:.0f}"

      group "icons row":
        box 260, 32
        layout LeftToRight
        itemSpacing 8
        icon "heart"
        text "heart label":
          characters "Heart"
        icon "cloud"
        text "cloud label":
          characters "Cloud"

      text "scroll one":
        characters "A bunch of text to test the scrolling, in any direction."
      text "scroll two":
        characters "Does it work?"

      for i in 0 ..< 10:
        text "time line " & $i:
          characters "Time will tell..."

      returnTest()

    if not showWindow:
      text "closed message":
        box 100, 100, 360, 32
        characters "Click anywhere to show the window"
      if window.buttonPressed[MouseLeft]:
        showWindow = true

    let ms = sk.avgFrameTime * 1000
    text "scale readout":
      box sk.size.x - 250, 20, 230, 22
      characters &"ui scale: {sk.uiScale:>4.2f}x (+/-)"
    text "time readout":
      box sk.size.x - 250, 48, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
