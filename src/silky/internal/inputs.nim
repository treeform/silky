import
  std/unicode,
  vmath,
  silky/common

when defined(silkyTesting):
  import silky/testwindow
else:
  import windy

const MaxPendingEvents = 65_536

type
  InputKind* = enum
    KeyDown, KeyUp, TextInput, TextCommit, NativeEdit

  InputEvent* = object
    kind*: InputKind
    button*: Button
    rune*: Rune
    text*: string
    edit*: TextInputEdit
    control*, shift*, alt*, super*: bool

  CallbackIdentity = tuple[code, environment: pointer]

  TextInputs* = ref object
    events: seq[InputEvent]
    active: bool
    editable: bool
    id: string
    epoch: uint64
    submitted: bool
    consumed: bool
    callbacks: array[6, CallbackIdentity]
    forwardedKeys: set[Button]
    consumedKeys: set[Button]
    releaseCallback: proc(button: Button)
    pendingText: TextInputState
    placementSerial, placementLayer, placementVertex: int

proc identity[T](callback: T): CallbackIdentity =
  ## Identifies a callback without retaining its closure environment.
  (rawProc(callback), rawEnv(callback))

proc focusEpoch*(inputs: TextInputs): uint64 =
  ## Returns the generation of the current text focus.
  inputs.epoch

when defined(silkyTesting):
  proc filterButtons*(
    inputs: TextInputs, buttons: array[Button, bool]
  ): array[Button, bool] =
    ## Hides keyboard state from normal controls during text entry.
    result = buttons
    if inputs.active:
      for button in Key0 .. Button.high:
        result[button] = false
else:
  proc filterButtons*(inputs: TextInputs, buttons: ButtonView): ButtonView =
    ## Hides keyboard state from normal controls during text entry.
    if inputs.active:
      ButtonView(set[Button](buttons) - {Key0 .. Button.high})
    else:
      buttons

proc stopInput*(inputs: TextInputs, window: Window) =
  ## Ends text capture and discards input for the previous field.
  if inputs.active:
    inc inputs.epoch
  inputs.active = false
  inputs.editable = false
  inputs.id.setLen(0)
  inputs.events.setLen(0)
  inputs.pendingText = TextInputState()
  window.setTextInputState(TextInputState())
  if window.runeInputEnabled:
    window.runeInputEnabled = false

proc modifiers(inputs: TextInputs, window: Window): InputEvent =
  ## Captures modifier state at the time of a callback.
  result.control = window.buttonDown[KeyLeftControl] or
    window.buttonDown[KeyRightControl]
  result.shift = window.buttonDown[KeyLeftShift] or
    window.buttonDown[KeyRightShift]
  result.alt = window.buttonDown[KeyLeftAlt] or
    window.buttonDown[KeyRightAlt]
  result.super = window.buttonDown[KeyLeftSuper] or
    window.buttonDown[KeyRightSuper]

proc addEvent(inputs: TextInputs, event: InputEvent) =
  ## Appends an event without coalescing or dropping earlier events.
  if inputs.events.len >= MaxPendingEvents:
    raise newException(SilkyError, "Too many pending text input events")
  inputs.events.add(event)

proc installPress(inputs: TextInputs, window: Window) =
  ## Installs this handler only when the window's callback changes.
  let windowPointer = cast[pointer](window)
  # The window owns the callback, so a pointer avoids a reference cycle.
  let previousPress = window.onButtonPress
  window.onButtonPress = proc(button: Button) =
    let window = cast[Window](windowPointer)
    if inputs.active and button >= Key0:
      var event = inputs.modifiers(window)
      event.kind = KeyDown
      event.button = button
      inputs.consumedKeys.incl(button)
      if inputs.editable and button == KeyV and
        (event.super or (event.control and not event.alt)):
          event.kind = TextCommit
          event.text = getClipboardString()
          if event.text.len > 0:
            inputs.addEvent(event)
          return
      inputs.addEvent(event)
      return
    if button >= Key0:
      inputs.forwardedKeys.incl(button)
      inputs.consumedKeys.excl(button)
    if previousPress != nil:
      previousPress(button)
  inputs.callbacks[0] = identity(window.onButtonPress)

proc installRelease(inputs: TextInputs, window: Window) =
  ## Installs this handler only when the window's callback changes.
  let windowPointer = cast[pointer](window)
  # The window owns the callback, so a pointer avoids a reference cycle.
  let previousRelease = window.onButtonRelease
  inputs.releaseCallback = previousRelease
  window.onButtonRelease = proc(button: Button) =
    let window = cast[Window](windowPointer)
    if inputs.active and button >= Key0:
      var event = inputs.modifiers(window)
      event.kind = KeyUp
      event.button = button
      inputs.consumedKeys.excl(button)
      inputs.addEvent(event)
      return
    if button >= Key0:
      inputs.forwardedKeys.excl(button)
      if button in inputs.consumedKeys:
        inputs.consumedKeys.excl(button)
        return
    if previousRelease != nil:
      previousRelease(button)
  inputs.callbacks[1] = identity(window.onButtonRelease)

proc installRune(inputs: TextInputs, window: Window) =
  ## Installs this handler only when the window's callback changes.
  let windowPointer = cast[pointer](window)
  # The window owns the callback, so a pointer avoids a reference cycle.
  let previousRune = window.onRune
  window.onRune = proc(rune: Rune) =
    let window = cast[Window](windowPointer)
    if inputs.active:
      if inputs.editable:
        var event = inputs.modifiers(window)
        event.kind = TextInput
        event.rune = rune
        inputs.addEvent(event)
      return
    if previousRune != nil:
      previousRune(rune)
  inputs.callbacks[2] = identity(window.onRune)

proc installFocus(inputs: TextInputs, window: Window) =
  ## Installs this handler only when the window's callback changes.
  let windowPointer = cast[pointer](window)
  # The window owns the callback, so a pointer avoids a reference cycle.
  let previousFocus = window.onFocusChange
  window.onFocusChange = proc() =
    inputs.stopInput(cast[Window](windowPointer))
    if previousFocus != nil:
      previousFocus()
  inputs.callbacks[3] = identity(window.onFocusChange)

proc installText(inputs: TextInputs, window: Window) =
  ## Captures complete native commits before a dictation tool restores state.
  let
    windowPointer = cast[pointer](window)
    previousText = window.onTextInput
  window.onTextInput = proc(text: string) =
    ## Preserves one native insertion as one ordered editing operation.
    let window = cast[Window](windowPointer)
    if inputs.active:
      if inputs.editable and text.len > 0:
        inputs.addEvent(InputEvent(kind: TextCommit, text: text))
      return
    if previousText != nil:
      previousText(text)
    elif window.onRune != nil:
      for rune in text.runes:
        window.onRune(rune)
  inputs.callbacks[4] = identity(window.onTextInput)

proc installEdit(inputs: TextInputs, window: Window) =
  ## Queues native accessibility edits in the same order as keyboard input.
  let previousEdit = window.onTextEdit
  window.onTextEdit = proc(edit: TextInputEdit) =
    ## Applies edits only to the field that currently owns text input.
    if inputs.active:
      if inputs.editable:
        inputs.addEvent(InputEvent(kind: NativeEdit, edit: edit))
      return
    if previousEdit != nil:
      previousEdit(edit)
  inputs.callbacks[5] = identity(window.onTextEdit)

proc overrideCallbacks(
  inputs: TextInputs, window: Window, initialize = false
) =
  ## Checks handlers without allocating closure state on unchanged frames.
  if initialize or identity(window.onButtonPress) != inputs.callbacks[0]:
    inputs.installPress(window)
  if initialize or identity(window.onButtonRelease) != inputs.callbacks[1]:
    inputs.installRelease(window)
  if initialize or identity(window.onRune) != inputs.callbacks[2]:
    inputs.installRune(window)
  if initialize or identity(window.onFocusChange) != inputs.callbacks[3]:
    inputs.installFocus(window)
  if initialize or identity(window.onTextInput) != inputs.callbacks[4]:
    inputs.installText(window)
  if initialize or identity(window.onTextEdit) != inputs.callbacks[5]:
    inputs.installEdit(window)

proc newTextInputs*(window: Window): TextInputs =
  ## Sets up all text input handling directly from the window.
  result = TextInputs()
  result.overrideCallbacks(window, initialize = true)
  result.stopInput(window)

proc beginInputFrame*(inputs: TextInputs, window: Window) =
  ## Refreshes input handlers and starts the input frame.
  if inputs == nil:
    raise newException(SilkyError, "Create Silky with newSilky before use")
  inputs.overrideCallbacks(window)
  inputs.submitted = false
  inputs.consumed = false
  inputs.pendingText = TextInputState()
  inputs.placementSerial = 0

proc textPlacementMark*(inputs: TextInputs): int =
  ## Marks the start of a deferred layout containing a focused editor.
  if inputs != nil:
    result = inputs.placementSerial

proc publishTextInput*(
  inputs: TextInputs, state: TextInputState, layer, firstVertex: int
) =
  ## Stages native editor state until layout placement is complete.
  inputs.pendingText = state
  inputs.placementLayer = layer
  inputs.placementVertex = firstVertex
  inc inputs.placementSerial

proc translateTextInput*(inputs: TextInputs, first: int, offset: Vec2) =
  ## Moves an editor published inside a deferred layout span.
  if inputs != nil and inputs.placementSerial > first:
    inputs.pendingText.bounds.x += offset.x
    inputs.pendingText.bounds.y += offset.y

proc translateTextInputVertices*(
  inputs: TextInputs, layer, first: int, offset: Vec2
) =
  ## Moves editor bounds along with their rendered vertices.
  if inputs != nil and inputs.placementSerial > 0 and
    inputs.placementLayer == layer and inputs.placementVertex >= first:
      inputs.pendingText.bounds.x += offset.x
      inputs.pendingText.bounds.y += offset.y

proc moveTextInputBehind*(
  inputs: TextInputs, layer, spanStart, chromeStart, total: int
) =
  ## Preserves the editor's vertex position when parent chrome is reordered.
  if inputs == nil or inputs.placementSerial == 0:
    return
  if inputs.placementLayer != layer or
    inputs.placementVertex < spanStart or inputs.placementVertex >= total:
      return
  if inputs.placementVertex < chromeStart:
    inputs.placementVertex += total - chromeStart
  else:
    inputs.placementVertex -= chromeStart - spanStart

proc submitInput*(
  inputs: TextInputs,
  window: Window,
  id: string,
  focused, editable: bool
) =
  ## Updates the active field without changing Windy's key state.
  if not focused:
    if inputs.active and inputs.id == id:
      inputs.stopInput(window)
    return
  if not inputs.active or inputs.id != id:
    inputs.events.setLen(0)
    inc inputs.epoch
    inputs.id = id
    inputs.active = true
    let releasedKeys = inputs.forwardedKeys
    inputs.forwardedKeys = {}
    inputs.consumedKeys = inputs.consumedKeys + releasedKeys
    if inputs.releaseCallback != nil:
      for button in releasedKeys:
        inputs.releaseCallback(button)
  inputs.editable = editable
  inputs.submitted = true
  if window.runeInputEnabled != editable:
    window.runeInputEnabled = editable

proc takeInput*(inputs: TextInputs): seq[InputEvent] =
  ## Takes the entire pending batch at most once in this UI frame.
  if inputs.consumed or not inputs.active:
    return
  inputs.consumed = true
  swap(result, inputs.events)

proc endInputFrame*(inputs: TextInputs, window: Window) =
  ## Ends capture when the active field was not submitted this frame.
  if not inputs.submitted:
    inputs.stopInput(window)
  elif inputs.editable and inputs.pendingText.id == inputs.id:
    window.setTextInputState(inputs.pendingText)
  else:
    window.setTextInputState(TextInputState())
