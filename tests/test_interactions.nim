## Mouse event batches must not lose release activation between rendered frames.
## Run with: nim r -d:silkyTesting tests/test_interactions.nim
import std/[options, tables]
import bumpy, silky, vmath

let window = newWindow(200, 200)
let sk = Silky(window: window)
let target = rect(20'f32, 20'f32, 100'f32, 40'f32)

proc sample(enabled = true): Interaction =
  sk.beginUI(window, window.size)
  result = sk.interact(target, enabled)
  sk.endUi()
  window.resetInputState()

window.moveMouse(50, 30)
discard sample()
doAssert sample() == Hovered
window.pressButton(MouseLeft)
doAssert sample() == Pressed
doAssert sample() == Held
window.releaseButton(MouseLeft)
doAssert sample() == Released
discard sample()

# A full click between two frames used to return Pressed and lose the release.
window.pressButton(MouseLeft)
window.releaseButton(MouseLeft)
doAssert sample() == Released
doAssert sample() == Hovered

window.pressButton(MouseLeft)
discard sample()
window.releaseButton(MouseLeft)
window.pressButton(MouseLeft)
doAssert sample() == Pressed
doAssert sample() == Held
window.releaseButton(MouseLeft)
doAssert sample() == Released
discard sample()

window.pressButton(MouseLeft)
window.releaseButton(MouseLeft)
doAssert sample(false) == Disabled

window.pressButton(MouseLeft)
window.moveMouse(190, 190)
window.releaseButton(MouseLeft)
doAssert sample() == ReleasedOutside
echo "Batched mouse interaction tests passed"

# Exercise the actual press-driven controls, using a small semantic atlas.
block:
  let atlas = SilkyAtlas(size: 64)
  for name in ["heart", "maximized", "minimized", "close", "scrubber.handle"]:
    atlas.entries[name] = Entry(width: 16, height: 16)
  let window = newWindow(240, 240)
  let sk = newSilky(window, atlas)
  var icons = 0
  var volume = 0'f32
  var show = true
  var panel: SubWindowState
  window.onFrame = proc() =
    sk.beginUI(window, window.size)
    sk.at = vec2(20, 20)
    clickableIcon "heart", true: inc icons
    sk.at = vec2(20, 60)
    scrubber "batch-test", volume, 0'f32, 1'f32
    panel = sk.subWindowStart(window, "batch-window", show,
      some(vec2(20, 120)), some(vec2(180, 100)))
    sk.subWindowEnd(window, panel)
    sk.endUi()

  proc clickAt(x, y: int, completed: bool) =
    window.moveMouse(x, y)
    window.pumpFrame(sk)
    window.pumpFrame(sk)
    window.pressButton(MouseLeft)
    if not completed:
      window.pumpFrame(sk)
    window.releaseButton(MouseLeft)
    window.pumpFrame(sk)
    window.pumpFrame(sk)

  for completed in [false, true]:
    let before = icons
    clickAt(24, 24, completed)
    doAssert icons == before + 1
    volume = 0
    clickAt(120, 64, completed)
    doAssert volume > 0.3 and volume < 0.7
    let stopped = volume
    window.moveMouse(40, 64)
    window.pumpFrame(sk)
    doAssert volume == stopped, "released scrubber must not keep dragging"
    clickAt(24 + sk.theme.border + sk.theme.textPadding,
      124 + sk.theme.border + sk.theme.textPadding, completed)
    doAssert panel.minimized
    clickAt(24 + sk.theme.border + sk.theme.textPadding,
      124 + sk.theme.border + sk.theme.textPadding, completed)
    doAssert not panel.minimized
  echo "Press-driven widget callback tests passed"
