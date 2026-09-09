import
  std/unicode,
  silky/common

when defined(silkyTesting):
  import silky/testwindow
else:
  import windy

when defined(emscripten) and not defined(silkyTesting):
  import browsers

const MaxPendingEvents = 65_536

type
  InputKind* = enum
    KeyDown, KeyUp, TextInput

  InputEvent* = object
    kind*: InputKind
    button*: Button
    rune*: Rune
    control*, shift*, alt*, super*: bool
    altGraph*: bool

  CallbackIdentity = tuple[code, environment: pointer]

  TextInputs* = ref object
    events: seq[InputEvent]
    active: bool
    editable: bool
    id: string
    epoch: uint64
    submitted: bool
    consumed: bool
    callbacks: array[4, CallbackIdentity]
    forwardedKeys: set[Button]
    consumedKeys: set[Button]
    releaseCallback: proc(button: Button)
    when defined(emscripten) and not defined(silkyTesting):
      browser: BrowserInputs

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
  if window.runeInputEnabled:
    window.runeInputEnabled = false

proc modifiers(inputs: TextInputs, window: Window): InputEvent =
  ## Captures modifier state at the time of a callback.
  when defined(emscripten) and not defined(silkyTesting):
    let bits = inputs.browser.modifiers
    if (bits and 16) != 0:
      result.control = (bits and 1) != 0
      result.shift = (bits and 2) != 0
      result.alt = (bits and 4) != 0
      result.super = (bits and 8) != 0
      result.altGraph = (bits and 32) != 0
      return
  result.control = window.buttonDown[KeyLeftControl] or
    window.buttonDown[KeyRightControl]
  result.shift = window.buttonDown[KeyLeftShift] or
    window.buttonDown[KeyRightShift]
  result.alt = window.buttonDown[KeyLeftAlt] or
    window.buttonDown[KeyRightAlt]
  result.super = window.buttonDown[KeyLeftSuper] or
    window.buttonDown[KeyRightSuper]

proc isKeyboard(inputs: TextInputs, button: Button): bool =
  ## Includes browser keys that Windy does not map to a button yet.
  when defined(emscripten) and not defined(silkyTesting):
    if (inputs.browser.modifiers and 16) != 0:
      return true
  button >= Key0

proc addEvent(inputs: TextInputs, event: InputEvent) =
  ## Appends an event without coalescing or dropping earlier events.
  if inputs.events.len >= MaxPendingEvents:
    raise newException(SilkyError, "Too many pending text input events")
  inputs.events.add(event)

proc overrideCallbacks(
  inputs: TextInputs, window: Window, initialize = false
) =
  ## Automatically installs handlers for any changed callback slots.
  let windowPointer = cast[pointer](window)
  # The window owns these callbacks, so a pointer avoids a reference cycle.
  if initialize or identity(window.onButtonPress) != inputs.callbacks[0]:
    let previousPress = window.onButtonPress
    window.onButtonPress = proc(button: Button) =
      let window = cast[Window](windowPointer)
      if inputs.active and inputs.isKeyboard(button):
        var event = inputs.modifiers(window)
        event.kind = KeyDown
        event.button = button
        inputs.consumedKeys.incl(button)
        inputs.addEvent(event)
        return
      if button >= Key0:
        inputs.forwardedKeys.incl(button)
        inputs.consumedKeys.excl(button)
      if previousPress != nil:
        previousPress(button)
    inputs.callbacks[0] = identity(window.onButtonPress)
  if initialize or identity(window.onButtonRelease) != inputs.callbacks[1]:
    let previousRelease = window.onButtonRelease
    inputs.releaseCallback = previousRelease
    window.onButtonRelease = proc(button: Button) =
      let window = cast[Window](windowPointer)
      if inputs.active and inputs.isKeyboard(button):
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
  if initialize or identity(window.onRune) != inputs.callbacks[2]:
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
  if initialize or identity(window.onFocusChange) != inputs.callbacks[3]:
    let previousFocus = window.onFocusChange
    window.onFocusChange = proc() =
      inputs.stopInput(cast[Window](windowPointer))
      if previousFocus != nil:
        previousFocus()
    inputs.callbacks[3] = identity(window.onFocusChange)

proc newTextInputs*(window: Window): TextInputs =
  ## Sets up all text input handling directly from the window.
  result = TextInputs()
  when defined(emscripten) and not defined(silkyTesting):
    result.browser = newBrowserInputs(window)
  result.overrideCallbacks(window, initialize = true)
  result.stopInput(window)

proc beginInputFrame*(inputs: TextInputs, window: Window) =
  ## Refreshes input handlers and starts the input frame.
  if inputs == nil:
    raise newException(SilkyError, "Create Silky with newSilky before use")
  inputs.overrideCallbacks(window)
  inputs.submitted = false
  inputs.consumed = false

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
