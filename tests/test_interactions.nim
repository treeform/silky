## Mouse event batches must not lose release activation between rendered frames.
## Run with: nim r -d:silkyTesting tests/test_interactions.nim
import bumpy, silky

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
