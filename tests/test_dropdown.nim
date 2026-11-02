import
  vmath,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("tests/data/", "tests/data/")
builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("tests/dist/test_dropdown_atlas.png")
var
  selected = 0
  resolution = 0

proc drawDropdown(sk: Silky, window: Window) =
  ## Draws a dropdown away from the origin to exercise scaled hit testing.
  sk.pushLayout(vec2(100, 100), vec2(240, 100))
  dropDown selected, [0, 1, 2]
  sk.popLayout()
  sk.pushLayout(vec2(100, 148), vec2(240, 100))
  dropDown resolution, [0, 10, 20]
  sk.popLayout()

proc click(harness: var TestHarness, position: Vec2) =
  ## Clicks a UI coordinate after warming the hover state.
  let pixels = (position * harness.sk.uiScale).ivec2
  harness.window.moveMouse(pixels.x, pixels.y)
  discard harness.pumpFrame(drawDropdown, 2)
  harness.window.pressButton(MouseLeft)
  discard harness.pumpFrame(drawDropdown)
  harness.window.releaseButton(MouseLeft)
  discard harness.pumpFrame(drawDropdown)

for scale in [1.0'f, 1.5'f, 2.0'f]:
  selected = 0
  resolution = 0
  dropDownStates.clear()
  var harness = newTestHarness("tests/dist/test_dropdown_atlas.png", 1200, 1000)
  harness.sk.uiScale = scale
  discard harness.pumpFrame(drawDropdown)
  let control = harness.findByText("0", "DropDown").rect
  harness.click(vec2(control.x + control.w / 2, control.y + control.h / 2))
  doAssert dropDownStates[cast[uint](addr selected)].open
  doAssert not dropDownStates[cast[uint](addr resolution)].open
  harness.click(vec2(control.x + control.w / 2, control.y + control.h * 2.5))
  doAssert selected == 1, "Dropdown selection failed at scale " & $scale
  doAssert not dropDownStates[cast[uint](addr selected)].open
  doAssert resolution == 0
  doAssert not dropDownStates[cast[uint](addr resolution)].open
  echo "Adjacent dropdown selection passed at scale ", scale

# A release over another control must not steal a press from the first one.
dropDownStates.clear()
selected = 0
resolution = 0
var harness = newTestHarness("tests/dist/test_dropdown_atlas.png", 1200, 1000)
discard harness.pumpFrame(drawDropdown)
let first = harness.findByText("0", "DropDown").rect
harness.window.moveMouse(int(first.x + 20), int(first.y + first.h / 2))
discard harness.pumpFrame(drawDropdown, 2)
harness.window.pressButton(MouseLeft)
discard harness.pumpFrame(drawDropdown)
harness.window.moveMouse(int(first.x + 20), int(148 + first.h / 2))
discard harness.pumpFrame(drawDropdown, 2)
harness.window.releaseButton(MouseLeft)
discard harness.pumpFrame(drawDropdown)
doAssert not dropDownStates[cast[uint](addr resolution)].open,
  "A dropdown must own the press before accepting the release"
echo "Dropdown presses cannot transfer to neighboring controls"
