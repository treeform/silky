import
  std/os,
  silky, silky/semantics

when not defined(silkyTesting):
  {.error: "Compile with -d:silkyTesting".}

const DataDirectory = currentSourcePath().parentDir / "data"

type Fixture = object
  harness: TestHarness
  id: string
  text: string
  password: bool

var
  atlas: SilkyAtlas
  nextId: int

block:
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir(DataDirectory, DataDirectory & DirSep)
  builder.addFont(DataDirectory / "IBMPlexSans-Regular.ttf", "Default", 18)
  atlas = builder.atlas

proc frame(fixture: var Fixture) =
  ## Draws and commits native state through the real ordered editor pipeline.
  fixture.harness.beginFrame()
  fixture.harness.sk.textBox(
    fixture.harness.window,
    fixture.id,
    fixture.text,
    240,
    80,
    wrapWords = false,
    singleLine = true,
    password = fixture.password
  )
  fixture.harness.endFrame()
  fixture.harness.window.resetInputState()

proc state(fixture: Fixture): TextBoxState =
  ## Returns the editor owned by this field.
  textBoxStates[fixture.id]

proc newFixture(text: string, password: bool): Fixture =
  ## Creates and focuses one editable field without a native window.
  inc nextId
  result.id = "secure-input-" & $nextId
  result.text = text
  result.password = password
  result.harness.window = newWindow()
  result.harness.sk = newSilky(result.harness.window, atlas)
  result.frame()
  result.state.focus(result.harness.sk, result.harness.window, result.id)
  result.state.selectAll()
  result.frame()

proc shortcut(window: Window, key, modifier: Button) =
  ## Queues one complete hardware keyboard shortcut between frames.
  window.pressButton(modifier)
  window.pressButton(key)
  window.releaseButton(key)
  window.releaseButton(modifier)

block:
  echo "Testing hardware copy and cut preserve secure fields and clipboard"
  for modifier in [KeyLeftSuper, KeyLeftControl]:
    var fixture = newFixture("hidden 雪", password = true)
    let originalSelection = fixture.state.selection
    setClipboardString("unrelated clipboard")
    for key in [KeyC, KeyX]:
      fixture.harness.window.shortcut(key, modifier)
      fixture.frame()
      doAssert fixture.text == "hidden 雪"
      doAssert fixture.state.selection == originalSelection
      doAssert getClipboardString() == "unrelated clipboard"
    fixture.harness.window.shortcut(KeyV, modifier)
    fixture.frame()
    doAssert fixture.text == "unrelated clipboard"

block:
  echo "Testing ordinary fields retain copy and cut"
  var fixture = newFixture("ordinary text", password = false)
  setClipboardString("old clipboard")
  fixture.harness.window.shortcut(KeyC, KeyLeftSuper)
  fixture.frame()
  doAssert getClipboardString() == "ordinary text"
  fixture.harness.window.shortcut(KeyX, KeyLeftSuper)
  fixture.frame()
  doAssert fixture.text.len == 0
  doAssert getClipboardString() == "ordinary text"

block:
  echo "Testing native secure-state publication and range edits"
  var fixture = newFixture("secret 雪", password = true)
  let window = fixture.harness.window
  when defined(ios):
    doAssert window.textInput.id == fixture.id
    doAssert window.textInput.password
    doAssert window.textInput.text == fixture.text
    doAssert window.textInput.selectionEnd == fixture.text.runeLen
  else:
    doAssert window.textInput.id.len == 0
    doAssert window.textInput.text.len == 0
  window.onTextEdit(TextInputEdit(
    kind: ReplaceText, start: 7, length: 1, text: "日"
  ))
  fixture.frame()
  doAssert fixture.text == "secret 日"
  fixture.password = false
  fixture.frame()
  doAssert window.textInput.id == fixture.id
  doAssert not window.textInput.password
  doAssert window.textInput.text == fixture.text
  fixture.password = true
  fixture.frame()
  when defined(ios):
    doAssert window.textInput.password
  else:
    doAssert window.textInput.id.len == 0
    doAssert window.textInput.text.len == 0

echo "All secure input tests passed."
