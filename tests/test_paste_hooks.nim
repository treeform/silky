import
  silky/internal/inputs, silky/testwindow

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

proc paste(window: Window, modifier = KeyLeftSuper) =
  ## Delivers the complete paste shortcut between UI frames.
  window.pressButton(modifier)
  window.pressButton(KeyV)
  window.releaseButton(KeyV)
  window.releaseButton(modifier)

proc commits(inputs: TextInputs): seq[string] =
  ## Returns only committed strings from the pending input batch.
  for event in inputs.takeInput():
    if event.kind == TextCommit:
      result.add(event.text)

block:
  echo "Testing custom paste consumption and normal text fallback"
  let
    window = newWindow()
    inputs = newTextInputs(window)
  var
    calls: seq[string]
    handled = true
  inputs.onPaste = proc(id: string): bool =
    ## Records the target field and optionally consumes its paste.
    calls.add(id)
    handled
  setClipboardString("normal text")
  inputs.beginInputFrame(window)
  inputs.submitInput(window, "composer", true, true)
  window.paste()
  doAssert calls == @["composer"]
  doAssert inputs.commits().len == 0
  doAssert not window.buttonDown[KeyV]
  doAssert not window.buttonDown[KeyLeftSuper]

  inputs.beginInputFrame(window)
  inputs.submitInput(window, "composer", true, true)
  handled = false
  window.paste(KeyLeftControl)
  doAssert calls == @["composer", "composer"]
  doAssert inputs.commits() == @["normal text"]

  inputs.beginInputFrame(window)
  inputs.submitInput(window, "settings", true, true)
  window.paste()
  doAssert calls[^1] == "settings"
  doAssert inputs.commits() == @["normal text"]

  inputs.beginInputFrame(window)
  inputs.submitInput(window, "settings", true, true)
  inputs.onPaste = nil
  window.paste()
  doAssert calls.len == 3
  doAssert inputs.commits() == @["normal text"]
  inputs.stopInput(window)

block:
  echo "Testing readonly and unfocused fields do not intercept paste"
  let
    window = newWindow()
    inputs = newTextInputs(window)
  var calls = 0
  inputs.onPaste = proc(id: string): bool =
    ## Counts unexpected calls from inactive or readonly fields.
    inc calls
    true
  window.paste()
  doAssert calls == 0
  inputs.beginInputFrame(window)
  inputs.submitInput(window, "reply", true, false)
  window.paste()
  doAssert calls == 0
  doAssert inputs.commits().len == 0
  inputs.stopInput(window)
  window.paste()
  doAssert calls == 0
  inputs.onPaste = nil

block:
  echo "Testing a paste callback cannot forward text after changing focus"
  let
    window = newWindow()
    inputs = newTextInputs(window)
  var forwarded = 0
  window.onButtonRelease = proc(button: Button) =
    ## Counts keyboard releases forwarded after the active field closes.
    inc forwarded
  inputs.beginInputFrame(window)
  inputs.submitInput(window, "composer", true, true)
  inputs.onPaste = proc(id: string): bool =
    ## Changes the active editor while declining the original paste.
    inputs.submitInput(window, "another", true, true)
    false
  setClipboardString("must not reach another field")
  window.paste()
  doAssert inputs.commits().len == 0
  doAssert forwarded == 0
  inputs.onPaste = proc(id: string): bool =
    ## Closes the editor while declining the original paste.
    inputs.stopInput(window)
    false
  inputs.beginInputFrame(window)
  inputs.submitInput(window, "composer", true, true)
  window.paste()
  doAssert inputs.commits().len == 0
  doAssert forwarded == 0
  inputs.onPaste = nil

echo "All paste hook tests passed."
