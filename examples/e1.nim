import opengl, windy, bumpy, vmath, chroma,
  ../src/silky

var window = newWindow("Silky Example 1", ivec2(800, 600))
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#000000").rgbx
  RibbonColor = parseHtmlColor("#273646").rgbx
  ScrubberColor = parseHtmlColor("#1D1D1D").rgbx
  m = 8f # Default margin

var sk = newSilky("examples/dist/atlas.png", "examples/dist/atlas.json")

var vibes = @[
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

window.onFrame = proc() =

  sk.beginFrame(window, window.size)
  sk.clearScreen(BackgroundColor)

  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.drawImage(
        "testTexture", 
        vec2(x.float32 * 256, y.float32 * 256),
        rgbx(100, 100, 100, 255)
      )

  # Header
  sk.pushFrame(sk.at, vec2(sk.size.x, 64))
  sk.drawRect(sk.at, sk.size, RibbonColor)

  sk.drawImage("ui/logo", sk.at)
  sk.drawText(
    "Title", 
    "Hello, World!", 
    sk.at + vec2(64, 36), 
    rgbx(255, 255, 255, 255)
  )

  var at = sk.at + vec2(sk.size.x - 16 - 32, 16)
  sk.drawImage("ui/heart", at)
  at -= vec2(32 + m, 0)
  sk.drawImage("ui/cloud", at)
  at -= vec2(32 + m, 0)

  sk.popFrame()

  # Scrubber
  sk.pushFrame(vec2(0, sk.size.y - 64*2), vec2(sk.size.x, 64))
  sk.drawRect(sk.at, sk.size, ScrubberColor)
  sk.popFrame()

  # Footer
  sk.pushFrame(vec2(0, sk.size.y - 64), vec2(sk.size.x, 64))
  sk.drawRect(sk.at, sk.size, RibbonColor)

  at = sk.at + vec2(16, 16)
  sk.drawImage("ui/rewindToStart", at)
  at += vec2(32 + m, 0)
  sk.drawImage("ui/stepBack", at)
  at += vec2(32 + m, 0)
  sk.drawImage("ui/play", at)
  at += vec2(32 + m, 0)
  sk.drawImage("ui/stepForward", at)
  at += vec2(32 + m, 0)
  sk.drawImage("ui/rewindToEnd", at)

  at = sk.at + vec2(sk.size.x - 16 - 32, 16)
  sk.drawImage("ui/heart", at)
  at -= vec2(32 + m, 0)
  sk.drawImage("ui/cloud", at)
  at -= vec2(32 + m, 0)
  sk.drawImage("ui/grid", at)
  at -= vec2(32 + m, 0)
  sk.drawImage("ui/eye", at)
  at -= vec2(32 + m, 0)
  sk.drawImage("ui/tack", at)
  at -= vec2(32 + m, 0)

  sk.popFrame()

  at = vec2(sk.size.x - (11 * (32 + m)), 100)
  for i, vibe in vibes:
    if i > 0 and i mod 10 == 0:
      at.x = (sk.size.x - (11 * (32 + m)))
      at.y += 32 + m
    sk.drawImage(vibe, at)
    at += vec2(32 + m, 0)


  sk.drawText(
    "Peragraph", 
    "Step: 1 of 10\nscore: 100\nlevel: 1\nwidth: 100\nheight: 100\nnum agents: 10", 
    sk.at + vec2(10, 200), 
    rgbx(255, 255, 255, 255)
  )

  sk.endFrame()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
