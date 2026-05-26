import
  std/[strformat],
  vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
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
    rectangle "menubar":
      box 0, 0, sk.size.x, 36
      patch "header.9patch", 6
      tint "#ffffff"
      group "menu roots":
        box 8, 4, 420, 28
        layout LeftToRight
        itemSpacing 4
        menuRoot "File", 72
        menuRoot "Edit", 72
        menuRoot "View", 72
        menuRoot "Help", 72

    case openMenu
    of "File":
      popupMenu "file", 8, 36, 200, 250:
        menuItem "Open":
          echo "Open"
        menuItem "Open Recent / File 1":
          echo "File 1"
        menuItem "Open Recent / File 2":
          echo "File 2"
        menuItem "Open Recent / File 3":
          echo "File 3"
        menuItem "Even More / Config A":
          echo "Config A"
        menuItem "Even More / Config B":
          echo "Config B"
        menuItem "Save":
          echo "Save"
        menuItem "Close":
          echo "Close"
    of "Edit":
      popupMenu "edit", 84, 36, 170, 110:
        menuItem "Cut":
          echo "Cut"
        menuItem "Copy":
          echo "Copy"
        menuItem "Paste":
          echo "Paste"
    of "View":
      popupMenu "view", 160, 36, 170, 110:
        menuItem "Fullscreen":
          echo "Fullscreen"
        menuItem "Windowed":
          echo "Windowed"
        menuItem "Maximized":
          echo "Maximized"
    of "Help":
      popupMenu "help", 236, 36, 130, 48:
        menuItem "About":
          echo "About"
    else:
      discard

    text "hint":
      box 24, 80, 460, 26
      characters "Menus are now authored as immediate DSL scopes."
      font "H1"

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  if window.buttonPressed[MouseLeft] and window.mousePos.y > 360:
    openMenu = ""

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
