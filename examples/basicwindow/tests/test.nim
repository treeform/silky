## Basic Window UI tests using semantic capture.
## Run with: nim r tests/test.nim (from basicwindow folder)

when not defined(silkyTesting):
  {.error: "Must compile with -d:silkyTesting".}

import
  std/unittest,
  silky,
  ../basicwindow {.all.}

proc resetState() =
  ## Resets all state to initial values.
  showWindow = true
  basicwindow.inputText = "Type here!"
  option = 1
  cumulative = false
  element = "Fire"
  power = "Medium"
  progress = 0.0
  howMuch = 30.0

suite "Basic Window UI":

  setup:
    resetState()
    window.pumpFrame(sk)

  test "initial state - SubWindow present with rect":
    let node = sk.semantic.root.findByName("A SubWindow", "SubWindow")
    check node != nil
    check node.rect.w > 0
    check node.rect.h > 0

  test "initial state - Hello world text":
    let node = sk.semantic.root.findByText("Hello world!")
    check node != nil
    check node.kind == "Text"

  test "initial state - Close Me button enabled":
    let node = sk.semantic.root.findByText("Close Me", "Button")
    check node != nil
    check node.state.enabled == true
    check node.state.pressed == false

  test "initial state - radio button Avg is checked":
    let
      avg = sk.semantic.root.findByText("Avg", "RadioButton")
      max = sk.semantic.root.findByText("Max", "RadioButton")
      min = sk.semantic.root.findByText("Min", "RadioButton")
    check avg != nil
    check max != nil
    check min != nil
    check avg.state.checked == true
    check max.state.checked == false
    check min.state.checked == false

  test "initial state - checkbox unchecked":
    let node = sk.semantic.root.findByText("Cumulative", "CheckBox")
    check node != nil
    check node.state.checked == false

  test "initial state - dropdowns show default values":
    let elem = sk.semantic.root.findByText("Fire", "DropDown")
    check elem != nil
    check elem.rect.w > 0

    let pwr = sk.semantic.root.findByText("Medium", "DropDown")
    check pwr != nil
    check pwr.rect.w > 0

  test "close button closes window":
    check showWindow == true
    window.clickButton(sk, "Close Me")
    window.pumpFrame(sk)
    check showWindow == false

    # SubWindow should have no children when closed.
    let node = sk.semantic.root.findByName("A SubWindow", "SubWindow")
    check node != nil
    check node.children.len == 0

  test "checkbox handles same-frame press release":
    check cumulative == false
    window.pumpFrame(sk)
    let node = sk.semantic.root.findByText("Cumulative", "CheckBox")
    check node != nil
    check node.rect.w > 0
    window.moveMouse(
      (node.rect.x + node.rect.w / 2).int,
      (node.rect.y + node.rect.h / 2).int
    )
    window.pumpFrame(sk)
    window.pressButton(MouseLeft)
    window.releaseButton(MouseLeft)
    window.pumpFrame(sk)
    check cumulative == true

  test "radio buttons update checked state":
    check option == 1

    window.clickText(sk, "Max", "RadioButton")
    window.pumpFrame(sk)
    check option == 2
    let
      max = sk.semantic.root.findByText("Max", "RadioButton")
      avg = sk.semantic.root.findByText("Avg", "RadioButton")
    check max.state.checked == true
    check avg.state.checked == false

    window.clickText(sk, "Min", "RadioButton")
    window.pumpFrame(sk)
    check option == 3
    let min = sk.semantic.root.findByText("Min", "RadioButton")
    check min.state.checked == true
    check sk.semantic.root.findByText("Max", "RadioButton").state.checked == false

    window.clickText(sk, "Avg", "RadioButton")
    window.pumpFrame(sk)
    check option == 1
    check sk.semantic.root.findByText("Avg", "RadioButton").state.checked == true
    check sk.semantic.root.findByText("Min", "RadioButton").state.checked == false

  test "checkbox toggles checked state":
    check cumulative == false
    let node0 = sk.semantic.root.findByText("Cumulative", "CheckBox")
    check node0.state.checked == false

    window.clickText(sk, "Cumulative", "CheckBox")
    check cumulative == true
    let node1 = sk.semantic.root.findByText("Cumulative", "CheckBox")
    check node1.state.checked == true 
 
    window.clickText(sk, "Cumulative", "CheckBox")
    check cumulative == false
    let node2 = sk.semantic.root.findByText("Cumulative", "CheckBox")
    check node2.state.checked == false

  test "progress bar label updates with value":
    check sk.semantic.root.findByText("Progress Bar:") != nil
    # After several frames, progress should advance and label stays.
    for i in 0 ..< 10:
      window.pumpFrame(sk)
    check sk.semantic.root.findByText("Progress Bar:") != nil

  test "scrubber label reflects initial value":
    let node = sk.semantic.root.findByText("How much: 30.00")
    check node != nil
    check node.kind == "Text"

  test "icons and group layout - both present":
    let
      heart = sk.semantic.root.findByText("Heart")
      cloud = sk.semantic.root.findByText("Cloud")
    check heart != nil
    check cloud != nil
    check heart.kind == "Text"
    check cloud.kind == "Text"

  test "widgets have non-zero rects":
    let
      btn = sk.semantic.root.findByText("Close Me", "Button")
      radio = sk.semantic.root.findByText("Avg", "RadioButton")
      cb = sk.semantic.root.findByText("Cumulative", "CheckBox")
      dd = sk.semantic.root.findByText("Fire", "DropDown")
    check btn.rect.w > 0
    check btn.rect.h > 0
    check radio.rect.w > 0
    check radio.rect.h > 0
    check cb.rect.w > 0
    check cb.rect.h > 0
    check dd.rect.w > 0
    check dd.rect.h > 0

  test "scrollable text content present":
    let
      scrollText = sk.semantic.root.findByText("A bunch of text to test the scrolling, in any direction.")
      doesItWork = sk.semantic.root.findByText("Does it work?")
      allTimeWillTell = sk.semantic.root.findAllByText("Time will tell...")
    check scrollText != nil
    check doesItWork != nil
    check allTimeWillTell.len == 10

  test "return test text present, unreachable text absent":
    check sk.semantic.root.findByText("Return Test") != nil
    check sk.semantic.root.findByText("Group") != nil
    check sk.semantic.root.findByText("You will not see this.") == nil
