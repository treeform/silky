import
  bumpy, vmath,
  silky

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

var
  direction = TopToBottom
  hugMode = 0
  clicks = 0
  indentCalls = 0
  padding = 0.0'f
  overflow = vec2(0, 0)

proc indentAmount(): float32 =
  ## Counts evaluation of an indent expression.
  inc indentCalls
  24

proc indentUi(sk: Silky, window: Window) =
  ## Places a child inside nested indentation and a padded hug.
  ui:
    group "outer":
      box 50, 50, 200, 200
      layout direction
      group "hugger":
        hug()
        layout direction
        horizontalPadding 3
        verticalPadding 3
        itemSpacing 0
        indent indentAmount():
          indent 8:
            rectangle "child":
              size 40, 20

proc clickUi(sk: Silky, window: Window) =
  ## Handles clicks after children for fixed and per-axis hug sizes.
  ui:
    group "outer":
      box 50, 50, 200, 200
      layout direction
      rectangle "clickable":
        size 40, 20
        layout direction
        case hugMode
        of 1:
          hugWidth()
        of 2:
          hugHeight()
        of 3:
          hug()
        else:
          discard
        itemSpacing 0
        rectangle "child":
          size 40, 20
        onClick:
          inc clicks

proc scrollUi(sk: Silky, window: Window) =
  ## Measures scroll overflow with the configured padding and direction.
  ui:
    rectangle "scroll":
      box 50, 50, 100, 100
      layout direction
      scrollable()
      horizontalPadding padding
      verticalPadding padding
      itemSpacing 0
      rectangle "child":
        size(
          100 - padding * 2 + overflow.x,
          100 - padding * 2 + overflow.y
        )

proc clickFrame(harness: var TestHarness) =
  ## Runs the full interaction lifecycle used by the example apps.
  harness.sk.beginUi(harness.window, harness.window.size)
  clickUi(harness.sk, harness.window)
  harness.sk.endUi()
  harness.window.resetInputState()

proc testIndent(atlas: SilkyAtlas) =
  ## Checks hug extents and single evaluation in every direction.
  for value in StackDirection:
    direction = value
    indentCalls = 0
    var harness = newTestHarness(atlas)
    discard harness.pumpFrame(indentUi)
    let hugger = harness.sk.semantic.root.findByName("hugger")
    doAssert hugger != nil
    case direction
    of TopToBottom, BottomToTop:
      doAssert hugger.rect.wh == vec2(78, 26)
    of LeftToRight, RightToLeft:
      doAssert hugger.rect.wh == vec2(46, 58)
    doAssert indentCalls == 1

proc testClicks(atlas: SilkyAtlas) =
  ## Checks clicks against the final rect for both hug axes.
  for value in StackDirection:
    direction = value
    for mode in 0 .. 3:
      hugMode = mode
      clicks = 0
      var harness = newTestHarness(atlas)
      harness.clickFrame()
      let node = harness.sk.semantic.root.findByName("clickable")
      doAssert node != nil
      harness.window.moveMouse(
        (node.rect.x + node.rect.w / 2).int,
        (node.rect.y + node.rect.h / 2).int
      )
      harness.clickFrame()
      harness.clickFrame()
      harness.window.pressButton(MouseLeft)
      harness.clickFrame()
      harness.window.releaseButton(MouseLeft)
      harness.clickFrame()
      doAssert clicks == 1, $direction & " hug mode " & $mode

proc testScroll(atlas: SilkyAtlas) =
  ## Checks exact-fit and overflowing content with non-default padding.
  for value in StackDirection:
    direction = value
    for inset in [0.0'f, 3, 10]:
      padding = inset
      for extra in [vec2(0, 0), vec2(20, 30)]:
        overflow = extra
        frameStates.clear()
        var harness = newTestHarness(atlas)
        discard harness.pumpFrame(scrollUi)
        frameStates["scroll"].scrollPos = vec2(10000, 10000)
        discard harness.pumpFrame(scrollUi, 2)
        doAssert frameStates["scroll"].scrollPos == extra

proc main() =
  ## Runs headless composition regressions without atlas files.
  let builder = newAtlasBuilder(64, 2)
  echo "Testing indented hug in four directions"
  testIndent(builder.atlas)
  echo "Testing fixed and hug click handlers in four directions"
  testClicks(builder.atlas)
  echo "Testing scroll padding in four directions"
  testScroll(builder.atlas)
  echo "All layout regression tests passed."

main()
