import
  pixie, vmath, chroma,
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

var
  showOverlapWindow = true
  behindClicked = false
  inFrontClicked = false
  foldout1Open = false
  foldout2Open = false
  foldout3Open = false

window.onFrame = proc() =
  sk.beginUI(window, window.size)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.drawImage(
        "testTexture",
        vec2(x.float32 * 256, y.float32 * 256),
        rgbx(30, 30, 30, 255)
      )

  ui:
    subWindow("Layouts", showOverlapWindow, vec2(200, 100), vec2(250, 400)):
      text "overlap label":
        characters "Two overlapping buttons:"

      group "overlap area":
        box 160, 55
        rectangle "behind":
          box 0, 20, 100, 32
          patch "button.9patch", 6
          onHover:
            patch "button.hover.9patch", 6
          onDown:
            patch "button.down.9patch", 6
          onClick:
            behindClicked = true
          text "behind label":
            box 8, 6, 84, 20
            characters "Behind"
            textAlign CenterAlign, MiddleAlign
        rectangle "front":
          box 15, 0, 100, 32
          patch "button.9patch", 6
          onHover:
            patch "button.hover.9patch", 6
          onDown:
            patch "button.down.9patch", 6
          onClick:
            inFrontClicked = true
          text "front label":
            box 8, 6, 84, 20
            characters "In Front"
            textAlign CenterAlign, MiddleAlign

      button(if foldout1Open: "- Section A" else: "+ Section A"):
        foldout1Open = not foldout1Open
      if foldout1Open:
        text "section a 1":
          characters "  Content of section A"
        text "section a 2":
          characters "  More content here"

      button(if foldout2Open: "- Section B" else: "+ Section B"):
        foldout2Open = not foldout2Open
      if foldout2Open:
        text "section b 1":
          characters "  Section B item 1"
        text "section b 2":
          characters "  Section B item 2"
        text "section b 3":
          characters "  Section B item 3"

      button(if foldout3Open: "- Section C" else: "+ Section C"):
        foldout3Open = not foldout3Open
      if foldout3Open:
        text "section c 1":
          characters "  Section C content"

    if not showOverlapWindow:
      text "closed message":
        box 100, 100, 360, 32
        characters "Click anywhere to show the window"
      if window.buttonPressed[MouseLeft]:
        showOverlapWindow = true

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
