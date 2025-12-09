import
  std/[unicode],
  windy

type
  InputTextState* = ref object
    runes*: seq[Rune]
    cursor*: int
    selector*: int
    scrollX*: float32
    focused*: bool

proc typeCharacter*(state: InputTextState, rune: Rune) =
  ## Adds a character to the text box.
  if state.cursor > state.runes.len:
    state.cursor = state.runes.len

  state.runes.insert(rune, state.cursor)
  inc state.cursor
  state.selector = state.cursor

proc backspace*(state: InputTextState, shift = false) =
  ## Backspace command.
  if state.cursor > 0:
    if state.cursor > state.runes.len:
      state.cursor = state.runes.len

    state.runes.delete(state.cursor - 1)
    dec state.cursor
    state.selector = state.cursor

proc delete*(state: InputTextState, shift = false) =
  ## Delete command.
  if state.cursor < state.runes.len:
    state.runes.delete(state.cursor)

proc left*(state: InputTextState, shift = false) =
  ## Moves the cursor left.
  if state.cursor > 0:
    dec state.cursor
    if not shift:
      state.selector = state.cursor

proc right*(state: InputTextState, shift = false) =
  ## Moves the cursor right.
  if state.cursor < state.runes.len:
    inc state.cursor
    if not shift:
      state.selector = state.cursor

proc home*(state: InputTextState, shift = false) =
  ## Moves the cursor to the start of the line.
  state.cursor = 0
  if not shift:
    state.selector = state.cursor

proc endKey*(state: InputTextState, shift = false) =
  ## Moves the cursor to the end of the line.
  state.cursor = state.runes.len
  if not shift:
    state.selector = state.cursor

proc selectAll*(state: InputTextState) =
  ## Selects all text.
  state.cursor = 0
  state.selector = state.runes.len

proc getText*(state: InputTextState): string =
  $state.runes

proc setText*(state: InputTextState, text: string) =
  state.runes = text.toRunes
  state.cursor = state.runes.len
  state.selector = state.runes.len

proc handleInput*(state: InputTextState, window: Window) =
  if not state.focused:
    return

  # Handle text input
  # Note: This relies on the window gathering runes, typically handled in the main loop or callback
  # For now, we assume we need to process keys here or use a buffer from window if available.
  # But typically handleInput would be called with events or checking window state.

  # Check standard keys
  if window.buttonPressed[KeyBackspace]:
    state.backspace(window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift])
  elif window.buttonPressed[KeyDelete]:
    state.delete(window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift])
  elif window.buttonPressed[KeyLeft]:
    state.left(window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift])
  elif window.buttonPressed[KeyRight]:
    state.right(window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift])
  elif window.buttonPressed[KeyHome]:
    state.home(window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift])
  elif window.buttonPressed[KeyEnd]:
    state.endKey(window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift])
  elif window.buttonPressed[KeyA] and (window.buttonDown[KeyLeftControl] or window.buttonDown[KeyRightControl] or window.buttonDown[KeyLeftSuper] or window.buttonDown[KeyRightSuper]):
    state.selectAll()
  elif window.buttonPressed[KeyC] and (window.buttonDown[KeyLeftControl] or window.buttonDown[KeyRightControl] or window.buttonDown[KeyLeftSuper] or window.buttonDown[KeyRightSuper]):
    # Copy
    discard
  elif window.buttonPressed[KeyV] and (window.buttonDown[KeyLeftControl] or window.buttonDown[KeyRightControl] or window.buttonDown[KeyLeftSuper] or window.buttonDown[KeyRightSuper]):
    # Paste
    let clipboard = getClipboardString()
    if clipboard.len > 0:
      for rune in clipboard.toRunes:
        state.typeCharacter(rune)
