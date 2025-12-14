
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
  "Menu System Demo",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#1a1a2e").rgbx

let sk = newSilky("dist/atlas.png", "dist/atlas.json")

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Clear screen with selected background color
  sk.clearScreen(BackgroundColor)

  menuBar:
    subMenu("File"):
      menuItem("Open"):
        echo "Open"
      subMenu("Open Recent"):
        menuItem("File 1"):
          echo "File 1"
        menuItem("File 2"):
          echo "File 2"
        menuItem("File 3"):
          echo "File 3"
        subMenu("Even More"):
          menuItem("Config A"):
            echo "Config A"
          menuItem("Config B"):
            echo "Config B"
      menuItem("Save"):
        echo "Save"
      menuItem("Close"):
        echo "Close"
    subMenu("Edit"):
      menuItem("Cut"):
        echo "Cut"
      menuItem("Copy"):
        echo "Copy"
      menuItem("Paste"):
        echo "Paste"
    subMenu("View"):
      menuItem("Fullscreen"):
        echo "Fullscreen"
      menuItem("Windowed"):
        echo "Windowed"
      menuItem("Maximized"):
        echo "Maximized"
    subMenu("Help"):
      menuItem("About"):
        echo "About"

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
