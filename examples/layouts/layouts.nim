import
  vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "Layouts",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "dist/atlas.png")

let overlap* = vec2(15, -35)

var
  showOverlapWindow = true
  behindClicked = false
  inFrontClicked = false
  foldout1Open = false
  foldout2Open = false
  foldout3Open = false

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(rgbx(30, 30, 30, 255))

  subWindow("Layouts", showOverlapWindow, vec2(200, 100), vec2(250, 400)):
    text("Two overlapping buttons:")

    var clicked = false

    button("Behind"):
      clicked = true

    behindClicked = clicked
    sk.at = sk.at + overlap

    button("In Front"):
      clicked = true

    inFrontClicked = clicked

    button(if foldout1Open: "- Section A" else: "+ Section A"):
      foldout1Open = not foldout1Open
    if foldout1Open:
      text("  Content of section A")
      text("  More content here")

    button(if foldout2Open: "- Section B" else: "+ Section B"):
      foldout2Open = not foldout2Open
    if foldout2Open:
      text("  Section B item 1")
      text("  Section B item 2")
      text("  Section B item 3")

    button(if foldout3Open: "- Section C" else: "+ Section C"):
      foldout3Open = not foldout3Open
    if foldout3Open:
      text("  Section C content")

  if not showOverlapWindow:
    if window.buttonPressed[MouseLeft]:
      showOverlapWindow = true
    sk.at = vec2(100, 100)
    text("Click anywhere to show the window")

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
