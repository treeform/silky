import
  std/unicode,
  silky, silky/semantics, silky/internal/inputs

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

type Fixture = object
  harness: TestHarness
  id: string
  text: string
  enabled: bool

var
  atlas: SilkyAtlas
  nextId: int

block:
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir("tests/data/", "tests/data/")
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
  atlas = builder.atlas

proc frame(fixture: var Fixture) =
  ## Draws one real textbox through the normal ordered input pipeline.
  fixture.harness.beginFrame()
  fixture.harness.sk.textBox(
    fixture.harness.window,
    fixture.id,
    fixture.text,
    240,
    120,
    wrapWords = true,
    enabled = fixture.enabled
  )
  fixture.harness.endFrame()
  fixture.harness.window.resetInputState()

proc state(fixture: Fixture): TextBoxState =
  ## Looks up the editor owned by the fixture's textbox.
  textBoxStates[fixture.id]

proc newFixture(text: string, enabled = true): Fixture =
  ## Creates and focuses one textbox with a distinct identity.
  inc nextId
  result.id = "input-hook-" & $nextId
  result.text = text
  result.enabled = enabled
  result.harness.window = newWindow()
  result.harness.sk = newSilky(result.harness.window, atlas)
  result.frame()
  let state = result.state()
  state.focus(result.harness.sk, result.harness.window, result.id)
  state.cursor = state.runes.len
  state.selector = state.cursor

proc tap(window: Window, button: Button) =
  ## Delivers a complete keyboard event pair between UI frames.
  window.pressButton(button)
  window.releaseButton(button)

block:
  echo "Testing hooks observe edits and consume arrows in event order"
  var
    fixture = newFixture("draft")
    kinds: seq[InputKind]
    contents: seq[string]
    cursors: seq[int]
  let
    state = fixture.state()
    window = fixture.harness.window
  state.onInput = proc(editor: TextBoxState, event: InputEvent): bool =
    ## Observes prior edits before replacing a consumed history arrow.
    kinds.add(event.kind)
    contents.add(editor.getText())
    cursors.add(editor.cursor)
    if event.kind == InputKind.KeyDown and event.button == KeyUp:
      editor.setText("old\nhistory")
      editor.cursor = editor.runes.len
      editor.selector = editor.cursor
      return true
  window.onTextInput("!")
  window.tap(KeyUp)
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText, start: 0, length: 3, text: "NEW"
  ))
  window.onRune(Rune('?'))
  fixture.frame()
  doAssert kinds == @[
    TextCommit, InputKind.KeyDown, InputKind.KeyUp, NativeEdit, TextInput
  ]
  doAssert contents == @[
    "draft", "draft!", "old\nhistory", "old\nhistory", "NEW\nhistory"
  ]
  doAssert cursors[2] == "old\nhistory".len
  doAssert cursors[3] == "old\nhistory".len
  doAssert fixture.text == "NEW?\nhistory"
  doAssert state.cursor == 4 and state.selector == 4
  doAssert not state.dirty
  doAssert state.layout.len == fixture.text.runeLen
  state.onInput = nil

block:
  echo "Testing declined events preserve navigation and ordinary editing"
  var
    observed = newFixture("abc")
    plain = newFixture("abc")
    calls = 0
  observed.state().onInput = proc(
    editor: TextBoxState, event: InputEvent
  ): bool =
    ## Counts events without replacing normal textbox behavior.
    inc calls
    false
  for fixture in [addr observed, addr plain]:
    let window = fixture[].harness.window
    window.tap(KeyLeft)
    window.onTextInput("x")
    fixture[].frame()
  doAssert calls == 3
  doAssert observed.text == "abxc"
  doAssert observed.text == plain.text
  doAssert observed.state().cursor == plain.state().cursor
  doAssert observed.state().selector == plain.state().selector
  doAssert observed.state().layout == plain.state().layout
  observed.state().onInput = nil

block:
  echo "Testing readonly input never invokes the editable hook"
  var
    fixture = newFixture("Read only", enabled = false)
    calls = 0
  let window = fixture.harness.window
  fixture.state().onInput = proc(
    editor: TextBoxState, event: InputEvent
  ): bool =
    ## Counts unexpected callbacks from read-only selection handling.
    inc calls
    true
  window.tap(KeyLeft)
  window.onTextInput("ignored")
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText, start: 0, length: 4, text: "ignored"
  ))
  fixture.frame()
  doAssert calls == 0
  doAssert fixture.text == "Read only"
  doAssert fixture.state().cursor == "Read only".len - 1
  fixture.state().onInput = nil

block:
  echo "Testing callback focus changes discard the entire stale remainder"
  for handled in [false, true]:
    var
      fixture = newFixture("original")
      calls = 0
    let
      state = fixture.state()
      window = fixture.harness.window
      inputs = fixture.harness.sk.textInputs
    state.onInput = proc(editor: TextBoxState, event: InputEvent): bool =
      ## Changes focus before the original event can modify this editor.
      inc calls
      inputs.submitInput(window, "another editor", true, true)
      handled
    window.onTextInput("stale")
    window.tap(KeyBackspace)
    window.onTextEdit(TextInputEdit(
      kind: ReplaceText, start: 0, length: 8, text: "stale native edit"
    ))
    fixture.frame()
    doAssert calls == 1
    doAssert fixture.text == "original"
    doAssert state.getText() == "original"
    state.onInput = nil

echo "All ordered input hook tests passed."
