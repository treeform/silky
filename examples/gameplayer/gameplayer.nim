import
  std/[strformat, strutils],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addDir("data/ui/", "data/")
builder.addDir("data/vibe/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png", "dist/atlas.json")

let window = newWindow(
  "Silky Example 1",
  ivec2(1200, 900),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#000000").rgbx
  RibbonColor = parseHtmlColor("#273646").rgbx
  ScrubberColor = parseHtmlColor("#1D1D1D").rgbx
  Margin = 12f

let
  sk = newSilky("dist/atlas.png", "dist/atlas.json")
  vibes = @[
  "vibe/alembic",
  "vibe/angry",
  "vibe/anxious",
  "vibe/assembler",
  "vibe/asterisk",
  "vibe/backpack",
  "vibe/beaming",
  "vibe/black-circle",
  "vibe/black-heart",
  "vibe/blue-circle",
  "vibe/blue-diamond",
  "vibe/blue-heart",
  "vibe/bow",
  "vibe/broken-heart",
  "vibe/brown-circle",
  "vibe/brown-heart",
  "vibe/brown-square",
  "vibe/carbon",
  "vibe/carbon_a",
  "vibe/carbon_b",
  "vibe/carrot",
  "vibe/charger",
  "vibe/chart-down",
  "vibe/chart-up",
  "vibe/chest",
  "vibe/clown",
  "vibe/coin",
  "vibe/compass",
  "vibe/confused",
  "vibe/corn",
  "vibe/crying-cat",
  "vibe/crying",
  "vibe/dagger",
  "vibe/default",
  "vibe/diamond",
  "vibe/divide",
  "vibe/down-left",
  "vibe/down-right",
  "vibe/down",
  "vibe/drooling",
  "vibe/eight",
  "vibe/factory",
  "vibe/fearful",
  "vibe/fire",
  "vibe/five",
  "vibe/four",
  "vibe/fuel",
  "vibe/gear",
  "vibe/germanium",
  "vibe/germanium_a",
  "vibe/germanium_b",
  "vibe/ghost",
  "vibe/green-circle",
  "vibe/green-heart",
  "vibe/grinning-big-eyes",
  "vibe/grinning-smiling-eyes",
  "vibe/grinning",
  "vibe/growing-heart",
  "vibe/halo",
  "vibe/hammer",
  "vibe/hash",
  "vibe/heart-arrow",
  "vibe/heart-decoration",
  "vibe/heart-exclamation",
  "vibe/heart-eyes",
  "vibe/heart-ribbon",
  "vibe/heart",
  "vibe/heart_a",
  "vibe/heart_b",
  "vibe/hundred",
  "vibe/kiss",
  "vibe/left",
  "vibe/light-shade",
  "vibe/lightning",
  "vibe/love-letter",
  "vibe/medium-shade",
  "vibe/minus",
  "vibe/moai",
  "vibe/money",
  "vibe/monocle",
  "vibe/mountain",
  "vibe/multiply",
  "vibe/nine",
  "vibe/numbers",
  "vibe/oil",
  "vibe/one",
  "vibe/orange-circle",
  "vibe/orange-heart",
  "vibe/orange-square",
  "vibe/oxygen",
  "vibe/oxygen_a",
  "vibe/oxygen_b",
  "vibe/package",
  "vibe/paperclip",
  "vibe/pin",
  "vibe/plug",
  "vibe/plus",
  "vibe/pouting",
  "vibe/purple-circle",
  "vibe/purple-heart",
  "vibe/purple-square",
  "vibe/pushpin",
  "vibe/red-circle",
  "vibe/red-heart",
  "vibe/red-triangle",
  "vibe/revolving-hearts",
  "vibe/right",
  "vibe/rock",
  "vibe/rocket",
  "vibe/rofl",
  "vibe/rolling-eyes",
  "vibe/rotate-clockwise",
  "vibe/rotate",
  "vibe/savoring",
  "vibe/seahorse",
  "vibe/seven",
  "vibe/shield",
  "vibe/silicon",
  "vibe/silicon_a",
  "vibe/silicon_b",
  "vibe/six",
  "vibe/skull-crossbones",
  "vibe/sleepy",
  "vibe/small-blue-diamond",
  "vibe/smiling",
  "vibe/smirking",
  "vibe/sobbing",
  "vibe/sparkle",
  "vibe/sparkling-heart",
  "vibe/squinting",
  "vibe/star-struck",
  "vibe/swearing",
  "vibe/swords",
  "vibe/target",
  "vibe/tears-of-joy",
  "vibe/ten",
  "vibe/test-tube",
  "vibe/three",
  "vibe/tree",
  "vibe/two-hearts",
  "vibe/two",
  "vibe/up-left",
  "vibe/up-right",
  "vibe/up",
  "vibe/wall",
  "vibe/water",
  "vibe/wave",
  "vibe/wheat",
  "vibe/white-circle",
  "vibe/white-heart",
  "vibe/white-square",
  "vibe/wood",
  "vibe/wrench",
  "vibe/yawning",
  "vibe/yellow-circle",
  "vibe/yellow-heart",
  "vibe/yellow-square",
  "vibe/zero",
  ]

var scrubValue: float32 = 0

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Draw map background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.layout.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  ribbon(sk.pos, vec2(sk.size.x, 64), RibbonColor):
    image("ui/logo")
    h1text("Hello, World!")

    sk.layout.at = sk.pos + vec2(sk.size.x - 100, 16)
    iconButton("ui/heart"):
      echo "heart"
    if sk.shouldShowTooltip:
      tooltip("Heart")  
    iconButton("ui/cloud"):
      echo "cloud"
    if sk.shouldShowTooltip:
      tooltip("Cloud")

  ribbon(vec2(0, sk.size.y - 64*2), vec2(sk.size.x, 66), ScrubberColor):
    # empty ribbon to fill with icons in the future
    discard

  ribbon(vec2(0, sk.size.y - 97), vec2(sk.size.x, 66), ScrubberColor):
    scrubber("timeline", scrubValue, 0, 1000, $int(scrubValue + 0.5))

  ribbon(vec2(0, sk.size.y - 64), vec2(sk.size.x, 64), RibbonColor):

    group(vec2(16, 16), TopToBottom):
      clickableIcon("ui/rewindToStart", true):
        echo "rewindToStart"
      if sk.shouldShowTooltip:
        tooltip("Rewind to Start")
      clickableIcon("ui/stepBack", true):
        echo "stepBack"
      if sk.shouldShowTooltip:
        tooltip("Step Back")
      clickableIcon("ui/play", true):
        echo "play"
      if sk.shouldShowTooltip:
        tooltip("Play")
      clickableIcon("ui/stepForward", true):
        echo "stepForward"
      if sk.shouldShowTooltip:
        tooltip("Step Forward")
      clickableIcon("ui/rewindToEnd", true):
        echo "rewindToEnd"
      if sk.shouldShowTooltip:
        tooltip("Rewind to End")

    # Position the second group relative to the right side of the window.
    sk.layout.at = sk.pos + vec2(sk.size.x - 240, 16)
    group(vec2(0, 0), TopToBottom):
      clickableIcon("ui/heart", true):
        echo "clickable heart"
      if sk.shouldShowTooltip:
        tooltip("Clickable Heart")
      clickableIcon("ui/cloud", true):
        echo "clickable cloud"
      if sk.shouldShowTooltip:
        tooltip("Clickable Cloud")
      clickableIcon("ui/grid", true):
        echo "grid"
      if sk.shouldShowTooltip:
        tooltip("Grid")
      clickableIcon("ui/eye", true):
        echo "eye"
      if sk.shouldShowTooltip:
        tooltip("Eye")
      clickableIcon("ui/tack", true):
        echo "tack"
      if sk.shouldShowTooltip:
        tooltip("Tack")

  frame("vibe-frame", vec2(sk.size.x - (16 * (32 + Margin)), 100) - vec2(14, 14), vec2(700, 600) + vec2(14, 14)):
    sk.layout.at = sk.pos + vec2(Margin, Margin) * 2
    for i, vibe in vibes:
      if i > 0 and i mod 13 == 0:
        sk.layout.at.x = sk.pos.x + Margin * 2
        sk.layout.at.y += 32 + Margin
      iconButton(vibe):
        echo vibe
      if sk.shouldShowTooltip:
        tooltip(vibe)

  group(vec2(10, 200), TopToBottom):
    text("Step: 1 of 10\nscore: 100\nlevel: 1\nwidth: 100\nheight: 100\nnum agents: 10")

  let ms = sk.avgFrameTime * 1000
  sk.layout.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
