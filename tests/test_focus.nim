import
  std/unicode,
  vmath,
  silky, silky/semantics, silky/internal/inputs

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

type InputMode = enum
  NoText, RuneInput, CommittedInput

proc tap(window: Window, button: Button) =
  ## Delivers a complete key or mouse event before the next draw.
  window.pressButton(button)
  window.releaseButton(button)

block:
  echo "Testing programmatic focus captures input before the first draw"
  let builder = newAtlasBuilder(1024, 4)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
  for oldFirst in [false, true]:
    for mode in InputMode:
      let
        suffix = $oldFirst & $mode
        oldId = "composer-" & suffix
        newId = "rename-" & suffix
      var
        harness = newTestHarness(builder.atlas)
        composer = "Composer draft"
        title = "Old title"
        showRename = false

      proc draw(sk: Silky, window: Window) =
        ## Draws the old owner before or after the newly focused popup.
        template oldField() =
          ## Draws the original composer without changing its draft.
          sk.at = vec2(20, 20)
          sk.textBox(window, oldId, composer, 240, 64, wrapWords = true)

        template renameField() =
          ## Draws the rename input once its popup has opened.
          if showRename:
            sk.at = vec2(20, 120)
            sk.textBox(
              window, newId, title, 240, 64,
              wrapWords = false, singleLine = true, submitOnEnter = true
            )

        if oldFirst:
          oldField()
          renameField()
        else:
          renameField()
          oldField()

      discard harness.pumpFrame(draw)
      let window = harness.window
      window.moveMouse(35, 35)
      window.tap(MouseLeft)
      discard harness.pumpFrame(draw)
      let oldState = textBoxStates[oldId]
      doAssert oldState.focused and window.runeInputEnabled

      harness.sk.textInputs.stopInput(window)
      doAssert not window.runeInputEnabled
      let state = TextBoxState(singleLine: true, dragging: true)
      state.setText(title)
      textBoxStates[newId] = state
      state.focus(harness.sk, window, newId)
      state.selectAll()
      showRename = true
      doAssert state.focused and not state.dragging
      doAssert state.cursorVisible
      doAssert window.runeInputEnabled
      doAssert state.selection == (0 .. title.runeLen)

      window.moveMouse(600, 400)
      window.releaseButton(MouseLeft)
      let expected =
        case mode
        of NoText:
          title
        of RuneInput:
          "R"
        of CommittedInput:
          "Renamed café"
      case mode
      of NoText:
        discard
      of RuneInput:
        window.typeRune(Rune('R'))
      of CommittedInput:
        window.onTextInput(expected)
      if mode != NoText:
        window.tap(KeyEnter)
      discard harness.pumpFrame(draw)
      doAssert state.focused and not oldState.focused
      doAssert title == expected
      doAssert composer == "Composer draft"
      doAssert state.submitted == (mode != NoText)
      doAssert window.textInput.id == newId
      doAssert window.textInput.text == expected
      doAssert not window.textInput.multiline
      if mode == NoText:
        doAssert state.selection == (0 .. title.runeLen),
          "The menu's stale mouse release must retain select-all."
      else:
        doAssert state.selection == (expected.runeLen .. expected.runeLen)
        doAssert state.undoStack.len == 1
        window.pressButton(KeyLeftSuper)
        window.tap(KeyZ)
        window.releaseButton(KeyLeftSuper)
        discard harness.pumpFrame(draw)
        doAssert title == "Old title"
        doAssert composer == "Composer draft"
      textBoxStates.del(oldId)
      textBoxStates.del(newId)

echo "All programmatic focus tests passed."
