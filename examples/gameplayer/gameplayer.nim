import
  std/[strformat],
  bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addDir("data/ui/", "data/")
builder.addDir("data/vibe/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "Silky Game Player",
  ivec2(1200, 900),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  RibbonColor = parseHtmlColor("#273646").rgbx
  ScrubberColor = parseHtmlColor("#1D1D1D").rgbx
  Margin = 12f

let
  sk = newSilky(window, "dist/atlas.png")
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

template ribbon(id: string, p, s: Vec2, ribbonTint: ColorRGBX, body: untyped) =
  rectangle id:
    box p.x, p.y, s.x, s.y
    tint ribbonTint
    layout LeftToRight
    horizontalPadding 16
    verticalPadding 12
    itemSpacing 12
    body

template vibeButton(id, imageName: string, x, y: float32) =
  rectangle id:
    box x, y, 40, 40
    patch "button.9patch", 8
    onHover:
      patch "button.hover.9patch", 8
    onDown:
      patch "button.down.9patch", 8
    onClick:
      echo imageName
    rectangle id & ":image":
      box 4, 4, 32, 32
      image imageName

window.onFrame = proc() =
  sk.beginUI(window, window.size)

  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.drawImage("testTexture", vec2(x.float32 * 256, y.float32 * 256), rgbx(30, 30, 30, 255))

  ui:
    ribbon("top ribbon", sk.pos, vec2(sk.size.x, 64), RibbonColor):
      rectangle "logo":
        box 0, 0, 48, 40
        image "ui/logo"
      text "title":
        box 62, 4, 320, 40
        characters "Hello, World!"
        font "H1"
      group "top actions":
        box sk.size.x - 160, 0, 120, 40
        layout LeftToRight
        itemSpacing 8
        iconButton "ui/heart":
          echo "heart"
        iconButton "ui/cloud":
          echo "cloud"

    ribbon("middle ribbon", vec2(0, sk.size.y - 128), vec2(sk.size.x, 66), ScrubberColor):
      discard

    ribbon("timeline ribbon", vec2(0, sk.size.y - 97), vec2(sk.size.x, 66), ScrubberColor):
      scrubber "timeline", scrubValue, 0, 1000, $int(scrubValue + 0.5)

    ribbon("transport ribbon", vec2(0, sk.size.y - 64), vec2(sk.size.x, 64), RibbonColor):
      group "transport buttons":
        box 16, 0, 260, 40
        layout LeftToRight
        itemSpacing 8
        clickableIcon "ui/rewindToStart", true:
          echo "rewindToStart"
        clickableIcon "ui/stepBack", true:
          echo "stepBack"
        clickableIcon "ui/play", true:
          echo "play"
        clickableIcon "ui/stepForward", true:
          echo "stepForward"
        clickableIcon "ui/rewindToEnd", true:
          echo "rewindToEnd"

      group "right tools":
        box sk.size.x - 260, 0, 240, 40
        layout LeftToRight
        itemSpacing 8
        clickableIcon "ui/heart", true:
          echo "clickable heart"
        clickableIcon "ui/cloud", true:
          echo "clickable cloud"
        clickableIcon "ui/grid", true:
          echo "grid"
        clickableIcon "ui/eye", true:
          echo "eye"
        clickableIcon "ui/tack", true:
          echo "tack"

    frame "vibe-frame":
      box sk.size.x - (16 * (32 + Margin)) - 14, 100 - 14, 700 + 14, 600 + 14
      patch "frame.9patch", 6
      layout TopToBottom
      horizontalPadding 24
      verticalPadding 24
      itemSpacing 0

      for i, vibe in vibes:
        let
          col = i mod 13
          row = i div 13
          x = col.float32 * (32 + Margin)
          y = row.float32 * (32 + Margin)
        vibeButton "vibe:" & $i, vibe, x, y

    frame "stats":
      box 10, 200, 220, 180
      patch "window.9patch", 14
      layout TopToBottom
      horizontalPadding 16
      verticalPadding 16
      text "stats text":
        characters "Step: 1 of 10\nscore: 100\nlevel: 1\nwidth: 100\nheight: 100\nnum agents: 10"

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
