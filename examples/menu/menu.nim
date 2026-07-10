import
  std/[strformat],
  vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "Menu System Demo",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const BackgroundColor = parseHtmlColor("#808080").rgbx

let sk = newSilky(window, "dist/atlas.png")

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    menuBar:
      menu "File":
        menuItem "Open":
          echo "Open"
        subMenu "Open Recent":
          menuItem "File 1":
            echo "File 1"
          menuItem "File 2":
            echo "File 2"
          menuItem "File 3":
            echo "File 3"
        subMenu "Even More":
          menuItem "Config A":
            echo "Config A"
          menuItem "Config B":
            echo "Config B"
        menuItem "Save":
          echo "Save"
        menuItem "Close":
          echo "Close"
      menu "Edit":
        menuItem "Cut":
          echo "Cut"
        menuItem "Copy":
          echo "Copy"
        menuItem "Paste":
          echo "Paste"
      menu "View":
        menuItem "Fullscreen":
          echo "Fullscreen"
        menuItem "Windowed":
          echo "Windowed"
        menuItem "Maximized":
          echo "Maximized"
      menu "Help":
        menuItem "About":
          echo "About"

      let
        ms = sk.avgFrameTime * 1000
        label = &"frame time: {ms:>7.3f}ms"
        labelSize = sk.getTextSize(sk.textStyle, label)
      discard sk.drawText(
        sk.textStyle,
        label,
        vec2(sk.size.x - labelSize.x - sk.theme.menuPadding.float32, 0),
        sk.theme.defaultTextColor
      )

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
