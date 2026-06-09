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
  earlyReturn = true # Demonstrates that early return from a group works.
  words = @["Alpha", "Bravo", "Charlie", "Delta"]
  wordsIdx = 0
  clickableEnabled = true

proc returnTest() =
  text("Return Test")
  group(vec2(8, 8), LeftToRight):
    text("Group")
    if earlyReturn:
      return
  text("You will not see this.")

window.onFrame = proc() =
  if window.buttonPressed[KeyEqual] or
    window.buttonPressed[NumpadAdd]:
    sk.uiScale = min(sk.uiScale + 0.25'f, 4.0'f)
  if window.buttonPressed[KeyMinus] or
    window.buttonPressed[NumpadSubtract]:
    sk.uiScale = max(sk.uiScale - 0.25'f, 0.25'f)

  sk.beginUI(window, window.size)

  sk.clearScreen(rgbx(30, 30, 30, 255))

  subWindow("A SubWindow", showWindow, vec2(100, 100), vec2(400, 700)):
    text("Hello world!")
    button("Close Me"):
      showWindow = false
    textInput("input", inputText)

    radioButton("Avg", option, 1)
    radioButton("Max", option, 2)
    radioButton("Min", option, 3)

    checkBox("Cumulative", cumulative)

    text("Select an option:")
    dropDown(element, ["Fire", "Water", "Earth", "Air"])
    dropDown(power, ["Low", "Medium", "High"])

    text("Progress Bar:")
    progressBar(progress, 0, 100)
    progress += 0.01
    if progress > 100.0:
      progress = 0.0

    text(&"How much: {howMuch:.2f}")
    scrubber("howMuch", howMuch, 0.0, 100.0)

    group(vec2(8, 8), LeftToRight):
      icon("heart")
      text("Heart")
      icon("cloud")
      text("Cloud")

    group(vec2(8, 8), LeftToRight):
      clickableIcon("heart", true):
        discard
      text("on")
      clickableIcon("heart", false):
        discard
      text("off")
      clickableIcon("heart", clickableEnabled):
        clickableEnabled = not clickableEnabled
      text("switch")

    group(vec2(8, 8), LeftToRight):
      iconButton("cloud"):
        wordsIdx = (wordsIdx + 1) mod words.len
      text(words[wordsIdx])

    text("A bunch of text to test the scrolling, in any direction.")
    text("Does it work?")

    for i in 0 ..< 10:
      text("Time will tell...")

    returnTest()

  if not showWindow:
    if window.buttonPressed[MouseLeft]:
      showWindow = true
    sk.at = vec2(100, 100)
    text("Click anywhere to show the window")

  let ms = sk.avgFrameTime * 1000
  sk.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"ui scale: {sk.uiScale:>4.2f}x (+/-)")
  sk.at = sk.pos + vec2(sk.size.x - 250, 48)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
