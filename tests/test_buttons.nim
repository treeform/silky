import
  bumpy, vmath,
  silky

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

var
  clicks: int
  enabled = true
  clipped = false
  evaluations: array[4, int]

proc drawButtons(sk: Silky, window: Window) =
  ## Draws a full-width model row and a legacy intrinsic button.
  sk.pushLayout(vec2(40, 30), vec2(260, 220))
  if clipped:
    sk.pushClipRect(rect(40, 30, 120, 80))
  button("Model", vec2(240, 64), enabled):
    inc clicks
  if clipped:
    sk.popClipRect()
  button("Legacy"):
    discard
  sk.popLayout()

proc click(harness: var TestHarness, position: Vec2) =
  ## Clicks a UI coordinate after warming the native hover state.
  let pixels = (position * harness.sk.uiScale).ivec2
  harness.window.moveMouse(pixels.x, pixels.y)
  discard harness.pumpFrame(drawButtons, 2)
  harness.window.pressButton(MouseLeft)
  discard harness.pumpFrame(drawButtons)
  harness.window.releaseButton(MouseLeft)
  discard harness.pumpFrame(drawButtons)

proc countedLabel(): string =
  ## Counts how many times a template evaluates its label expression.
  inc evaluations[0]
  "Counted"

proc countedSize(): Vec2 =
  ## Counts how many times a template evaluates its minimum size.
  inc evaluations[1]
  vec2(180, 64)

proc countedEnabled(): bool =
  ## Counts how many times a template evaluates its enabled expression.
  inc evaluations[2]
  true

proc countedError(): bool =
  ## Counts how many times a template evaluates its error expression.
  inc evaluations[3]
  false

proc drawCounted(sk: Silky, window: Window) =
  ## Exercises the full overload inside an actual deferred DSL group.
  ui:
    group "menu":
      box 40, 30, 260, 300
      button(
        countedLabel(), countedSize(), countedEnabled(), countedError()
      ):
        discard
      button("Minimum", vec2(180, 32)):
        discard
      button("Enabled", true):
        discard
      button("Error", true, false):
        discard
      button("Too small", vec2(1)):
        discard

block:
  echo "Testing minimum button size preserves native hit testing"
  let builder = newAtlasBuilder(1024, 4)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
  for scale in [1.0'f, 1.25'f, 1.5'f, 2.0'f]:
    var harness = newTestHarness(builder.atlas, 1200, 1000)
    harness.sk.uiScale = scale
    clicks = 0
    enabled = true
    clipped = false
    discard harness.pumpFrame(drawButtons)
    let
      model = harness.findByText("Model", "Button")
      legacy = harness.findByText("Legacy", "Button")
      intrinsic = harness.sk.getTextSize("Default", "Legacy") +
        vec2(harness.sk.theme.padding.float32 * 2)
      rightEdge = model.rect.xy + vec2(model.rect.w - 2, model.rect.h / 2)
    doAssert model.rect.wh == vec2(240, 64)
    doAssert legacy.rect.wh == intrinsic
    let pixels = (rightEdge * scale).ivec2
    harness.window.moveMouse(pixels.x, pixels.y)
    discard harness.pumpFrame(drawButtons, 2)
    doAssert harness.findByText("Model", "Button").state.hovered
    harness.click(rightEdge)
    doAssert clicks == 1

    enabled = false
    discard harness.pumpFrame(drawButtons)
    doAssert not harness.findByText("Model", "Button").state.enabled
    harness.click(rightEdge)
    doAssert clicks == 1
    doAssert not harness.findByText("Model", "Button").state.hovered

    enabled = true
    clipped = true
    harness.click(rightEdge)
    doAssert clicks == 1
    doAssert not harness.findByText("Model", "Button").state.hovered
    harness.click(model.rect.xy + vec2(16, model.rect.h / 2))
    doAssert clicks == 2

  echo "Testing sized button arguments are evaluated once per frame"
  var harness = newTestHarness(builder.atlas)
  evaluations = [0, 0, 0, 0]
  for frame in 1 .. 3:
    discard harness.pumpFrame(drawCounted)
    doAssert evaluations == [frame, frame, frame, frame]
    doAssert harness.findByText("Counted", "Button").rect.wh == vec2(180, 64)
    doAssert harness.findByText("Minimum", "Button").rect.w == 180
    doAssert harness.findByText("Too small", "Button").rect.wh ==
      harness.sk.getTextSize("Default", "Too small") +
        vec2(harness.sk.theme.padding.float32 * 2)

echo "All native button interaction tests passed."
