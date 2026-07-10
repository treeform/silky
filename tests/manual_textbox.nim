## Demonstrates a resizable multi-line text box.
##
## The text box supports typing, cursor navigation, selection via mouse and
## keyboard, copy/cut/paste, undo/redo, word wrap, and scroll. Drag the
## sliders to resize the text box.

import
  std/[strformat],
  opengl, windy, bumpy, vmath, chroma,
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
  "Text Box Example",
  ivec2(900, 800),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx
  SampleText = """Hello!
Short line.
A slightly longer line to test medium wrapping behavior.
The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump. The five boxing wizards jump quickly.
OK.
Word wrap splits text at word boundaries when it would exceed the maximum width.
Hi.
Supercalifragilisticexpialidocious is a very long word that tests character-level fallback wrapping.
Done."""
  Margin = 20.0f

let sk = newSilky(window, "tests/dist/atlas.png")

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

var
  boxWidth = 500.0f
  boxHeight = 400.0f
  wordWrapOn = true
  disabledOn = false
  errorOn = false
  passwordOn = false
  numbersOnly = false
  singleLineText = "Single line input"
  numberText = "12345"
  sampleText = SampleText

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    text "title":
      box Margin, Margin, 500, 40
      characters "Text Box Example"
      font "H1"
      tint sk.theme.textH1Color

    group "controls":
      box Margin, 70, 600, 280
      layout TopToBottom
      itemSpacing 8
      scrubber("width", boxWidth, 100.0, 800.0, &"{boxWidth:.0f} px")
      scrubber("height", boxHeight, 50.0, 700.0, &"{boxHeight:.0f} px")
      checkBox "Word wrap", wordWrapOn
      checkBox "Disabled", disabledOn
      checkBox "Error", errorOn
      checkBox "Password", passwordOn
      checkBox "Numbers only", numbersOnly

      let digitChars = "0123456789".toRunes
      if passwordOn:
        passwordInput("single", singleLineText, not disabledOn, errorOn)
      elif numbersOnly:
        textInput(
          "numbers",
          numberText,
          not disabledOn,
          errorOn,
          digitChars
        )
      else:
        textInput("single", singleLineText, not disabledOn, errorOn)

      textBox(
        "main",
        sampleText,
        boxWidth,
        boxHeight,
        wrapWords = wordWrapOn,
        isEnabled = not disabledOn,
        isError = errorOn
      )

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, Margin, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
