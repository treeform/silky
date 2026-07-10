import
  std/[tables, unicode, times],
  vmath, bumpy, chroma,
  silky/atlas

## Multi-line text box widget.
##
## Features:
## * Typing at location of cursor.
## * Cursor going left and right.
## * Backspace and delete.
## * Cursor going up and down must take into account font and line wrap.
## * Clicking should select a character edge. Closest edge wins.
## * Click and drag should select text, selected text will be between text cursor and select cursor.
## * Any insert when typing or copy pasting and have selected text, it should get removed and then do normal action.
## * Copy text should set it to system clipboard.
## * Cut text should copy and remove selected text.
## * Paste text should paste at current text cursor, if there is selection it needs to be removed.
## * Clicking before text should select first character.
## * Clicking at the end of text should select last character.
## * Click at the end of the end of the line should select character before the new line.
## * Click at the end of the start of the line should select character first character and not the newline.
## * Double click should select current word and space (TODO: stop on non-word characters, TODO: enter word selection mode).
## * Double click again should select current paragraph.
## * Double click again should select everything.
## * TODO: Selecting during word selection mode should select whole words.
## * Text area needs to be able to have margins that can be clicked.
## * There should be a scroll bar and a scroll window.
## * Scroll window should stay with the text cursor.
## * Backspace and delete with selected text remove selected text and don't perform their normal action.

when defined(silkyTesting):
  import silky/[semantic, testing, profiles]
  proc setClipboardString(value: string) =
    ## Stub for setting clipboard in test mode.
    discard
else:
  import silky/contexts, windy

const
  LF = Rune(10)
  CR = Rune(13)
  Space = Rune(32)
  CursorWidth* = 2.0f
  DoubleClickTime = 0.4
  SelectionColor = rgbx(30, 60, 130, 128)

when defined(macos):
  const TextBoxScrollSpeed = 10.0f
else:
  const TextBoxScrollSpeed = -10.0f

type
  TextBoxState* = ref object
    ## State for a multi-line text box widget.
    runes*: seq[Rune]
    cursor*: int
    selector*: int
    scrollPos*: Vec2
    savedX*: float32
    focused*: bool
    layout*: seq[Rect]
    dirty*: bool
    undoStack*: seq[(seq[Rune], int)]
    redoStack*: seq[(seq[Rune], int)]
    clickCount*: int
    lastClickTime*: float64
    dragging*: bool
    lineHeight*: float32
    boxSize*: Vec2
    lastMaxWidth*: float32
    blinkTime*: float64
    wordWrap*: bool
    scrollingY*: bool
    scrollingX*: bool
    scrollDragOffset*: Vec2
    singleLine*: bool
    enabled*: bool = true
    password*: bool
    passwordChar*: Rune = Rune('*')
    allowedChars*: seq[Rune]
    textCache: string
    textCacheValid: bool
    displayCache: string
    displayCacheValid: bool

var
  textBoxStates*: Table[string, TextBoxState]

proc vec2(v: SomeNumber): Vec2 =
  ## Create a Vec2 from a single number.
  vec2(v.float32, v.float32)

proc vec2[A, B](x: A, y: B): Vec2 =
  ## Create a Vec2 from two numbers.
  vec2(x.float32, y.float32)

proc isAllowed*(state: TextBoxState, rune: Rune): bool =
  ## Returns true if the rune is allowed in this text box.
  ## Empty allowedChars means all characters are allowed.
  state.allowedChars.len == 0 or rune in state.allowedChars

proc resetBlink*(state: TextBoxState) =
  ## Resets the cursor blink timer so the cursor is immediately visible.
  state.blinkTime = epochTime()

proc cursorVisible*(state: TextBoxState): bool =
  ## Returns true when the blinking cursor should be drawn.
  ## Blinks 0.5s on, 0.5s off, always starting visible after a reset.
  ((epochTime() - state.blinkTime) * 2).int mod 2 == 0

proc invalidateTextCaches(state: TextBoxState) {.inline.} =
  ## Marks cached UTF-8 text as stale after rune edits.
  state.textCacheValid = false
  state.displayCacheValid = false

proc markTextDirty(state: TextBoxState) {.inline.} =
  ## Marks layout and UTF-8 caches dirty after content changes.
  state.dirty = true
  state.invalidateTextCaches()

proc getText*(state: TextBoxState): string =
  ## Returns the current text content.
  if not state.textCacheValid:
    state.textCache = $state.runes
    state.textCacheValid = true
  state.textCache

proc displayText*(state: TextBoxState): lent string =
  ## Returns the text to display. In password mode, all chars are masked.
  if not state.displayCacheValid:
    if state.password:
      state.displayCache.setLen(0)
      for _ in state.runes:
        state.displayCache.add($state.passwordChar)
    else:
      state.displayCache = state.getText()
    state.displayCacheValid = true
  state.displayCache

proc sameText*(state: TextBoxState, text: string): bool =
  ## Compares rune content to a UTF-8 string without allocating.
  var
    i = 0
    runeIdx = 0
  while i < text.len and runeIdx < state.runes.len:
    var rune: Rune
    fastRuneAt(text, i, rune, true)
    if rune != state.runes[runeIdx]:
      return false
    inc runeIdx
  result = i == text.len and runeIdx == state.runes.len

proc setText*(state: TextBoxState, text: string) =
  ## Sets the text content and resets cursor to end.
  ## In single-line mode, newlines are converted to spaces.
  ## Disallowed characters are removed.
  state.runes = text.toRunes
  if state.singleLine:
    for i in 0 ..< state.runes.len:
      if state.runes[i] == LF or state.runes[i] == CR:
        state.runes[i] = Space
  if state.allowedChars.len > 0:
    var filtered: seq[Rune]
    for r in state.runes:
      if r in state.allowedChars:
        filtered.add(r)
    state.runes = filtered
  state.cursor = state.runes.len
  state.selector = state.cursor
  state.dirty = true
  state.invalidateTextCaches()

proc selection*(state: TextBoxState): HSlice[int, int] =
  ## Returns the ordered selection range.
  min(state.cursor, state.selector) .. max(state.cursor, state.selector)

proc computeLayout*(state: TextBoxState, fontData: FontAtlas, maxWidth: float32) =
  ## Computes per-character selection rectangles in local coordinates.
  ## Mirrors the glyph-walking logic from drawText but stores positions
  ## instead of emitting GPU vertices.
  state.layout.setLen(0)
  state.lineHeight = fontData.lineHeight
  state.lastMaxWidth = maxWidth
  var currentPos = vec2(0, 0)
  var i = 0
  while i < state.runes.len:
    let rune = state.runes[i]
    let displayRune =
      if state.password:
        state.passwordChar
      else:
        rune
    if rune == LF:
      # Newline gets a zero-width rect at line end.
      state.layout.add rect(currentPos.x, currentPos.y, 0, fontData.lineHeight)
      currentPos.x = 0
      currentPos.y += fontData.lineHeight
      inc i
      continue
    # Word wrap: at the start of a word check if it fits on this line.
    if state.wordWrap and maxWidth < float32.high and
        currentPos.x > 0 and rune != Rune(32):
      let isWordStart = (i == 0) or
        state.runes[i - 1] == Rune(32) or
        state.runes[i - 1] == LF
      if isWordStart:
        var
          wordW = 0.0f
          j = i
        while j < state.runes.len and
            state.runes[j] != Rune(32) and
            state.runes[j] != LF:
          var wordEntry: ptr LetterEntry
          if fontData.lookupLetter(state.runes[j], 0, wordEntry):
            wordW += wordEntry.advance
          inc j
        if currentPos.x + wordW > maxWidth:
          currentPos.x = 0
          currentPos.y += fontData.lineHeight
    var entry: ptr LetterEntry
    if not fontData.lookupLetter(displayRune, 0, entry):
      state.layout.add rect(currentPos.x, currentPos.y, 0, fontData.lineHeight)
      inc i
      continue
    # Character-level wrap fallback for words wider than maxWidth.
    if state.wordWrap and maxWidth < float32.high and
        currentPos.x >= maxWidth:
      currentPos.x = 0
      currentPos.y += fontData.lineHeight
    state.layout.add rect(
      currentPos.x, currentPos.y, entry.advance, fontData.lineHeight
    )
    currentPos.x += entry.advance
    # Kerning.
    if i < state.runes.len - 1:
      currentPos.x += fontData.lookupKerning(displayRune, state.runes[i + 1])
    inc i
  state.dirty = false

proc pickGlyphAt*(state: TextBoxState, pos: Vec2): int =
  ## Finds the character index closest to the given position.
  ## Returns -1 if no character found on that line.
  var minGlyph = -1
  var minDistance = -1.0f
  for i, selectRect in state.layout:
    if selectRect.y <= pos.y and pos.y < selectRect.y + selectRect.h:
      let dist = abs(pos.x - selectRect.x)
      if minDistance < 0 or dist < minDistance:
        minDistance = dist
        minGlyph = i
  return minGlyph

proc getSelectionRects*(layout: seq[Rect], start, stop: int): seq[Rect] =
  ## Computes merged selection highlight rectangles for a range.
  if start == stop:
    return
  for i, selectRect in layout:
    if i >= start and i < stop:
      if result.len > 0:
        let onSameLine = result[^1].y == selectRect.y and
          result[^1].h == selectRect.h
        let notTooFar = selectRect.x - result[^1].x < result[^1].w * 2
        if onSameLine and notTooFar:
          result[^1].w = selectRect.x - result[^1].x + selectRect.w
          continue
      result.add selectRect

proc innerHeight*(state: TextBoxState): float32 =
  ## Returns the total content height.
  if state.layout.len > 0:
    let lastPos = state.layout[^1]
    return lastPos.y + lastPos.h
  return state.lineHeight

proc innerWidth*(state: TextBoxState): float32 =
  ## Returns the widest line in the content.
  for r in state.layout:
    let lineEnd = r.x + r.w
    if lineEnd > result:
      result = lineEnd

proc locationRect*(state: TextBoxState, loc: int): Rect =
  ## Returns the rectangle where the cursor should be drawn.
  if state.layout.len > 0:
    if loc >= state.layout.len:
      let selectRect = state.layout[^1]
      if state.runes.len > 0 and state.runes[^1] == LF:
        result.x = 0
        result.y = selectRect.y + state.lineHeight
      else:
        result = selectRect
        result.x += selectRect.w
    else:
      result = state.layout[loc]
  result.w = CursorWidth
  result.h = state.lineHeight

proc cursorPos*(state: TextBoxState): Vec2 =
  ## Returns the position of the text cursor.
  state.locationRect(state.cursor).xy

proc undoSave*(state: TextBoxState) =
  ## Saves current state for undo.
  state.undoStack.add((state.runes, state.cursor))
  state.redoStack.setLen(0)

proc undo*(state: TextBoxState) =
  ## Goes back in history.
  if state.undoStack.len > 0:
    state.redoStack.add((state.runes, state.cursor))
    (state.runes, state.cursor) = state.undoStack.pop()
    state.selector = state.cursor
    state.markTextDirty()
    state.resetBlink()

proc redo*(state: TextBoxState) =
  ## Goes forward in history.
  if state.redoStack.len > 0:
    state.undoStack.add((state.runes, state.cursor))
    (state.runes, state.cursor) = state.redoStack.pop()
    state.selector = state.cursor
    state.markTextDirty()
    state.resetBlink()

proc removedSelection*(state: TextBoxState): bool =
  ## Removes selected runes and returns true if anything was removed.
  let sel = state.selection
  if sel.a != sel.b:
    for i in countdown(sel.b - 1, sel.a):
      state.runes.delete(i)
    state.cursor = sel.a
    state.selector = state.cursor
    state.markTextDirty()
    return true
  return false

proc removeSelection*(state: TextBoxState) =
  ## Removes selected runes.
  discard state.removedSelection()

proc scrollToCursor*(state: TextBoxState) =
  ## Adjusts scroll so the cursor stays visible.
  let r = state.locationRect(state.cursor)
  if r.y < state.scrollPos.y:
    state.scrollPos.y = r.y
  if r.y + r.h > state.scrollPos.y + state.boxSize.y:
    state.scrollPos.y = r.y + r.h - state.boxSize.y
  if not state.wordWrap:
    if r.x < state.scrollPos.x:
      state.scrollPos.x = r.x
    if r.x + CursorWidth > state.scrollPos.x + state.boxSize.x:
      state.scrollPos.x = r.x + CursorWidth - state.boxSize.x

proc typeCharacter*(state: TextBoxState, rune: Rune) =
  ## Adds a character at the cursor position.
  ## Blocked by: disabled, single-line newlines, and allowedChars filter.
  if not state.enabled:
    return
  if state.singleLine and (rune == LF or rune == CR):
    return
  if not state.isAllowed(rune):
    return
  state.undoSave()
  state.removeSelection()
  if state.cursor >= state.runes.len:
    state.runes.add(rune)
  else:
    state.runes.insert(rune, state.cursor)
  inc state.cursor
  state.selector = state.cursor
  state.markTextDirty()
  state.scrollToCursor()
  state.resetBlink()

proc typeCharacters*(state: TextBoxState, s: string) =
  ## Adds multiple characters at the cursor position.
  ## In single-line mode, newlines are converted to spaces. Disabled blocks edits.
  if not state.enabled:
    return
  state.undoSave()
  state.removeSelection()
  for rune in runes(s):
    if rune == CR:
      continue
    var r = rune
    if state.singleLine and r == LF:
      r = Space
    if not state.isAllowed(r):
      continue
    if state.cursor >= state.runes.len:
      state.runes.add(r)
    else:
      state.runes.insert(r, state.cursor)
    inc state.cursor
  state.selector = state.cursor
  state.markTextDirty()
  state.scrollToCursor()
  state.resetBlink()

proc copyText*(state: TextBoxState): string =
  ## Returns the text in the current selection.
  let sel = state.selection
  if sel.a != sel.b:
    return $state.runes[sel.a ..< sel.b]

proc pasteText*(state: TextBoxState, s: string) =
  ## Pastes a string at the cursor. Disabled state blocks edits.
  if not state.enabled:
    return
  state.typeCharacters(s)
  state.savedX = state.cursorPos.x

proc cutText*(state: TextBoxState): string =
  ## Cuts selected text and returns it. Disabled state returns copy only.
  result = state.copyText()
  if not state.enabled or result == "":
    return
  state.undoSave()
  state.removeSelection()
  state.savedX = state.cursorPos.x
  state.resetBlink()

proc backspace*(state: TextBoxState) =
  ## Deletes the character before the cursor. Disabled state blocks edits.
  if not state.enabled:
    return
  if state.cursor != state.selector:
    state.undoSave()
    discard state.removedSelection()
    state.resetBlink()
    return
  if state.cursor > 0:
    state.undoSave()
    state.runes.delete(state.cursor - 1)
    dec state.cursor
    state.selector = state.cursor
    state.markTextDirty()
  state.scrollToCursor()
  state.resetBlink()

proc delete*(state: TextBoxState) =
  ## Deletes the character after the cursor. Disabled state blocks edits.
  if not state.enabled:
    return
  if state.cursor != state.selector:
    state.undoSave()
    discard state.removedSelection()
    state.resetBlink()
    return
  if state.cursor < state.runes.len:
    state.undoSave()
    state.runes.delete(state.cursor)
    state.markTextDirty()
  state.scrollToCursor()
  state.resetBlink()

proc backspaceWord*(state: TextBoxState) =
  ## Deletes the word before the cursor. If starting on a space, eats spaces
  ## first then the word. Otherwise just eats the word.
  if not state.enabled:
    return
  if state.cursor != state.selector:
    state.undoSave()
    discard state.removedSelection()
    state.resetBlink()
    return
  if state.cursor > 0:
    state.undoSave()
    if state.runes[state.cursor - 1].isWhiteSpace():
      while state.cursor > 0 and
          state.runes[state.cursor - 1].isWhiteSpace():
        state.runes.delete(state.cursor - 1)
        dec state.cursor
    while state.cursor > 0 and
        not state.runes[state.cursor - 1].isWhiteSpace():
      state.runes.delete(state.cursor - 1)
      dec state.cursor
    state.selector = state.cursor
    state.markTextDirty()
  state.scrollToCursor()
  state.resetBlink()

proc deleteWord*(state: TextBoxState) =
  ## Deletes the word after the cursor, then any trailing spaces.
  if not state.enabled:
    return
  if state.cursor != state.selector:
    state.undoSave()
    discard state.removedSelection()
    state.resetBlink()
    return
  if state.cursor < state.runes.len:
    state.undoSave()
    while state.cursor < state.runes.len and
        not state.runes[state.cursor].isWhiteSpace():
      state.runes.delete(state.cursor)
    while state.cursor < state.runes.len and
        state.runes[state.cursor].isWhiteSpace():
      state.runes.delete(state.cursor)
    state.markTextDirty()
  state.scrollToCursor()
  state.resetBlink()

proc left*(state: TextBoxState, shift = false) =
  ## Moves the cursor left by one character.
  if state.cursor > 0:
    dec state.cursor
    if not shift:
      state.selector = state.cursor
    state.savedX = state.cursorPos.x
  state.scrollToCursor()
  state.resetBlink()

proc right*(state: TextBoxState, shift = false) =
  ## Moves the cursor right by one character.
  if state.cursor < state.runes.len:
    inc state.cursor
    if not shift:
      state.selector = state.cursor
    state.savedX = state.cursorPos.x
  state.scrollToCursor()
  state.resetBlink()

proc down*(state: TextBoxState, shift = false) =
  ## Moves the cursor down one line.
  if state.layout.len > 0:
    let curPos = state.cursorPos
    let index = state.pickGlyphAt(
      vec2(state.savedX, curPos.y + state.lineHeight * 1.5))
    if index != -1:
      state.cursor = index
      if not shift:
        state.selector = state.cursor
    elif curPos.y >= state.layout[^1].y:
      state.cursor = state.runes.len
      if not shift:
        state.selector = state.cursor
  state.scrollToCursor()
  state.resetBlink()

proc up*(state: TextBoxState, shift = false) =
  ## Moves the cursor up one line.
  if state.layout.len > 0:
    let curPos = state.cursorPos
    let index = state.pickGlyphAt(
      vec2(state.savedX, curPos.y - state.lineHeight * 0.5))
    if index != -1:
      state.cursor = index
      if not shift:
        state.selector = state.cursor
    elif curPos.y <= state.layout[0].y:
      state.cursor = 0
      if not shift:
        state.selector = state.cursor
  state.scrollToCursor()
  state.resetBlink()

proc leftWord*(state: TextBoxState, shift = false) =
  ## Moves the cursor left by one word.
  if state.cursor > 0:
    dec state.cursor
  while state.cursor > 0 and
      not state.runes[state.cursor - 1].isWhiteSpace():
    dec state.cursor
  if not shift:
    state.selector = state.cursor
  state.savedX = state.cursorPos.x
  state.scrollToCursor()
  state.resetBlink()

proc rightWord*(state: TextBoxState, shift = false) =
  ## Moves the cursor right by one word.
  if state.cursor < state.runes.len:
    inc state.cursor
  while state.cursor < state.runes.len and
      not state.runes[state.cursor].isWhiteSpace():
    inc state.cursor
  if not shift:
    state.selector = state.cursor
  state.savedX = state.cursorPos.x
  state.scrollToCursor()
  state.resetBlink()

proc startOfLine*(state: TextBoxState, shift = false) =
  ## Moves the cursor to the start of the current line.
  while state.cursor > 0 and state.runes[state.cursor - 1] != LF:
    dec state.cursor
  if not shift:
    state.selector = state.cursor
  state.savedX = state.cursorPos.x
  state.scrollToCursor()
  state.resetBlink()

proc endOfLine*(state: TextBoxState, shift = false) =
  ## Moves the cursor to the end of the current line.
  while state.cursor < state.runes.len and state.runes[state.cursor] != LF:
    inc state.cursor
  if not shift:
    state.selector = state.cursor
  state.savedX = state.cursorPos.x
  state.scrollToCursor()
  state.resetBlink()

proc pageUp*(state: TextBoxState, shift = false) =
  ## Moves the cursor up by half the box height.
  if state.layout.len == 0:
    return
  let
    curPos = state.cursorPos
    pos = vec2(state.savedX, curPos.y - state.boxSize.y * 0.5)
    index = state.pickGlyphAt(pos)
  if index != -1:
    state.cursor = index
    if not shift:
      state.selector = state.cursor
  elif pos.y <= state.layout[0].y:
    state.cursor = 0
    if not shift:
      state.selector = state.cursor
  state.scrollToCursor()
  state.resetBlink()

proc pageDown*(state: TextBoxState, shift = false) =
  ## Moves the cursor down by half the box height.
  if state.layout.len == 0:
    return
  let
    curPos = state.cursorPos
    pos = vec2(state.savedX, curPos.y + state.boxSize.y * 0.5)
    index = state.pickGlyphAt(pos)
  if index != -1:
    state.cursor = index
    if not shift:
      state.selector = state.cursor
  elif pos.y > state.layout[^1].y:
    state.cursor = state.runes.len
    if not shift:
      state.selector = state.cursor
  state.scrollToCursor()
  state.resetBlink()

proc mouseAction*(state: TextBoxState, mousePos: Vec2, click = true,
    shift = false) =
  ## Handles a mouse click or drag action on the text.
  let index = state.pickGlyphAt(mousePos)
  if index != -1 and index < state.runes.len:
    state.cursor = index
    if state.runes[index] != LF:
      let selectRect = state.layout[index]
      let pickOffset = mousePos.x - selectRect.x
      if pickOffset > selectRect.w / 2:
        inc state.cursor
  else:
    if mousePos.y < 0:
      state.cursor = 0
    elif mousePos.y >= state.innerHeight:
      state.cursor = state.runes.len
  state.savedX = mousePos.x
  if not shift and click:
    state.selector = state.cursor
  state.scrollToCursor()
  state.resetBlink()

proc selectAll*(state: TextBoxState) =
  ## Selects all text.
  state.cursor = 0
  state.selector = state.runes.len

proc selectWord*(state: TextBoxState, mousePos: Vec2) =
  ## Selects the word under the mouse position (double click).
  state.mouseAction(mousePos, click = true)
  while state.cursor > 0 and
      not state.runes[state.cursor - 1].isWhiteSpace():
    dec state.cursor
  while state.selector < state.runes.len and
      not state.runes[state.selector].isWhiteSpace():
    inc state.selector

proc selectParagraph*(state: TextBoxState, mousePos: Vec2) =
  ## Selects the paragraph under the mouse position (triple click).
  state.mouseAction(mousePos, click = true)
  while state.cursor > 0 and state.runes[state.cursor - 1] != LF:
    dec state.cursor
  while state.selector < state.runes.len and
      state.runes[state.selector] != LF:
    inc state.selector

proc scrollBy*(state: TextBoxState, amount, viewportHeight: float32) =
  ## Scrolls the text box vertically by the given amount.
  state.scrollPos.y += amount
  let maxScroll = max(0.0f, state.innerHeight - viewportHeight)
  state.scrollPos.y = clamp(state.scrollPos.y, 0.0f, maxScroll)

proc handleKeyboard*(
  state: TextBoxState,
  window: Window,
  inputRunes: seq[Rune],
  ctrl, shift, alt: bool,
  wordWrap: bool
) =
  ## Processes keyboard input for the text box.
  # On Mac: Option = word-level, Cmd = line/document-level.
  # On Windows/Linux: Ctrl = word-level, Home/End = line, Ctrl+Home/End = document.
  when defined(macosx):
    let wordMod = alt
    let lineMod = ctrl
  else:
    let wordMod = ctrl
    let lineMod = false
  for r in inputRunes:
    state.typeCharacter(r)
  if window.buttonPressed[KeyBackspace]:
    if wordMod: state.backspaceWord()
    else: state.backspace()
  elif window.buttonPressed[KeyDelete]:
    if wordMod: state.deleteWord()
    else: state.delete()
  elif window.buttonPressed[KeyLeft]:
    if wordMod: state.leftWord(shift)
    elif lineMod: state.startOfLine(shift)
    else: state.left(shift)
  elif window.buttonPressed[KeyRight]:
    if wordMod: state.rightWord(shift)
    elif lineMod: state.endOfLine(shift)
    else: state.right(shift)
  elif window.buttonPressed[KeyUp]:
    if lineMod:
      state.cursor = 0
      if not shift: state.selector = state.cursor
    else: state.up(shift)
  elif window.buttonPressed[KeyDown]:
    if lineMod:
      state.cursor = state.runes.len
      if not shift: state.selector = state.cursor
    else: state.down(shift)
  elif window.buttonPressed[KeyHome]:
    if ctrl:
      state.cursor = 0
      if not shift: state.selector = state.cursor
    else: state.startOfLine(shift)
  elif window.buttonPressed[KeyEnd]:
    if ctrl:
      state.cursor = state.runes.len
      if not shift: state.selector = state.cursor
    else: state.endOfLine(shift)
  elif window.buttonPressed[KeyPageUp]:
    state.pageUp(shift)
  elif window.buttonPressed[KeyPageDown]:
    state.pageDown(shift)
  elif window.buttonPressed[KeyEnter]:
    if not state.singleLine:
      state.typeCharacter(LF)
  elif ctrl:
    if window.buttonPressed[KeyA]:
      state.selectAll()
    elif window.buttonPressed[KeyC]:
      let copied = state.copyText()
      if copied.len > 0:
        setClipboardString(copied)
    elif window.buttonPressed[KeyX]:
      let cut = state.cutText()
      if cut.len > 0:
        setClipboardString(cut)
    elif window.buttonPressed[KeyV]:
      let clip = getClipboardString()
      if clip.len > 0:
        state.pasteText(clip)
    elif window.buttonPressed[KeyZ]:
      if shift: state.redo()
      else: state.undo()
    elif window.buttonPressed[KeyY]:
      state.redo()

proc drawScrollbars*(sk: Silky, state: TextBoxState, window: Window,
    outerRect, innerRect: Rect, mouseVec: Vec2, clipRect: Rect) =
  ## Draws scrollbar tracks and handles, and processes drag interaction.
  let contentH = state.innerHeight
  let contentW = state.innerWidth
  let scrollMaxY = max(0.0f, contentH - innerRect.h)
  let scrollMaxX = max(0.0f, contentW - innerRect.w)
  let hasScrollY = contentH > innerRect.h
  let hasScrollX = not state.wordWrap and contentW > innerRect.w
  # Release scrollbar drag when mouse released.
  if state.scrollingY and
      (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    state.scrollingY = false
  if state.scrollingX and
      (window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]):
    state.scrollingX = false
  # Y scrollbar.
  if hasScrollY:
    let trackRect = rect(
      outerRect.x + outerRect.w - 10,
      innerRect.y + 2,
      8,
      innerRect.h - 4 - (if hasScrollX: 10.0f else: 0.0f)
    )
    sk.draw9Patch("scrollbar.track.9patch", 4, trackRect.xy, trackRect.wh)
    let posPct = if scrollMaxY > 0: state.scrollPos.y / scrollMaxY else: 0.0f
    let sizePct = innerRect.h / contentH
    let handleRect = rect(
      trackRect.x,
      trackRect.y + (trackRect.h - trackRect.h * sizePct) * posPct,
      8,
      trackRect.h * sizePct
    )
    if state.scrollingY:
      let relY = mouseVec.y - state.scrollDragOffset.y - trackRect.y
      let availH = trackRect.h - handleRect.h
      if availH > 0:
        state.scrollPos.y = clamp(relY / availH, 0.0f, 1.0f) * scrollMaxY
    elif mouseVec.overlaps(handleRect) and mouseVec.overlaps(clipRect):
      if window.buttonPressed[MouseLeft]:
        state.scrollingY = true
        state.scrollDragOffset.y = mouseVec.y - handleRect.y
    sk.draw9Patch("scrollbar.9patch", 4, handleRect.xy, handleRect.wh)
  # X scrollbar.
  if hasScrollX:
    let trackRect = rect(
      innerRect.x + 2,
      outerRect.y + outerRect.h - 10,
      innerRect.w - 4 - (if hasScrollY: 10.0f else: 0.0f),
      8
    )
    sk.draw9Patch("scrollbar.track.9patch", 4, trackRect.xy, trackRect.wh)
    let posPct = if scrollMaxX > 0: state.scrollPos.x / scrollMaxX else: 0.0f
    let sizePct = innerRect.w / contentW
    let handleRect = rect(
      trackRect.x + (trackRect.w - trackRect.w * sizePct) * posPct,
      trackRect.y,
      trackRect.w * sizePct,
      8
    )
    if state.scrollingX:
      let relX = mouseVec.x - state.scrollDragOffset.x - trackRect.x
      let availW = trackRect.w - handleRect.w
      if availW > 0:
        state.scrollPos.x = clamp(relX / availW, 0.0f, 1.0f) * scrollMaxX
    elif mouseVec.overlaps(handleRect) and mouseVec.overlaps(clipRect):
      if window.buttonPressed[MouseLeft]:
        state.scrollingX = true
        state.scrollDragOffset.x = mouseVec.x - handleRect.x
    sk.draw9Patch("scrollbar.9patch", 4, handleRect.xy, handleRect.wh)

proc textBox*(
  sk: Silky,
  window: Window,
  id: string,
  t: var string,
  boxWidth, boxHeight: float32,
  wrapWords: bool,
  singleLine: bool = false,
  enabled: bool = true,
  error: bool = false,
  password: bool = false,
  passwordChar: Rune = Rune('*'),
  allowedChars: seq[Rune] = default(seq[Rune])
) {.measure.} =
  ## Text box widget with editing, selection, and scroll.
  ## When disabled, text can be selected and copied but not modified.
  ## Error is a visual-only state that changes the border and text color.
  ## Password mode masks displayed characters with the given char.
  ## allowedChars filters which characters can be typed or pasted.
  var state: TextBoxState
  let effectiveWrap = if singleLine: false else: wrapWords
  if id notin textBoxStates:
    let newState = TextBoxState(
      dirty: true, wordWrap: effectiveWrap, singleLine: singleLine,
      password: password, passwordChar: passwordChar,
      allowedChars: allowedChars)
    newState.setText(t)
    textBoxStates[id] = newState
  state = textBoxStates[id]
  state.enabled = enabled
  state.allowedChars = allowedChars
  if state.password != password:
    state.password = password
    state.dirty = true
    state.displayCacheValid = false
  state.passwordChar = passwordChar
  if state.singleLine != singleLine:
    state.singleLine = singleLine
    state.dirty = true
  if state.wordWrap != effectiveWrap:
    state.wordWrap = effectiveWrap
    state.dirty = true
  if not state.focused and not state.sameText(t):
    state.setText(t)
  let
    fontData = sk.atlas.fonts[sk.textStyle]
    padding = sk.theme.padding.float32
    outerRect = rect(sk.at, vec2(boxWidth, boxHeight))
    innerRect = rect(
      sk.at.x + padding, sk.at.y + padding,
      boxWidth - padding * 2, boxHeight - padding * 2
    )
  state.boxSize = vec2(innerRect.w, innerRect.h)
  if state.dirty or state.layout.len == 0 or
      state.lastMaxWidth != innerRect.w:
    state.computeLayout(fontData, innerRect.w)
  let ctrl = window.buttonDown[KeyLeftControl] or
    window.buttonDown[KeyRightControl] or
    window.buttonDown[KeyLeftSuper] or
    window.buttonDown[KeyRightSuper]
  let shift = window.buttonDown[KeyLeftShift] or
    window.buttonDown[KeyRightShift]
  let alt = window.buttonDown[KeyLeftAlt] or
    window.buttonDown[KeyRightAlt]
  let mouseVec = sk.mousePos
  let mouseInside = mouseVec.overlaps(outerRect) and
    mouseVec.overlaps(sk.clipRect)
  let onScrollbar = mouseInside and not mouseVec.overlaps(innerRect)
  if window.buttonPressed[MouseLeft]:
    if mouseInside and not onScrollbar:
      state.focused = true
      let localMouse = mouseVec - innerRect.xy + state.scrollPos
      let now = epochTime()
      if now - state.lastClickTime < DoubleClickTime:
        inc state.clickCount
      else:
        state.clickCount = 1
      state.lastClickTime = now
      case state.clickCount:
      of 1:
        state.mouseAction(localMouse, click = true, shift = shift)
        state.dragging = true
      of 2: state.selectWord(localMouse)
      of 3: state.selectParagraph(localMouse)
      else: state.selectAll()
    elif not mouseInside:
      state.focused = false
  if state.dragging and not state.scrollingX and not state.scrollingY:
    if window.buttonDown[MouseLeft] and not window.buttonPressed[MouseLeft]:
      let localMouse = mouseVec - innerRect.xy + state.scrollPos
      state.mouseAction(localMouse, click = false, shift = true)
    if window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]:
      state.dragging = false
  if state.focused:
    state.handleKeyboard(window, sk.inputRunes, ctrl, shift, alt, state.wordWrap)
    t = state.getText()
  if state.dirty:
    state.computeLayout(fontData, innerRect.w)
  let maxScrollY = max(0.0f, state.innerHeight - innerRect.h)
  state.scrollPos.y = clamp(state.scrollPos.y, 0.0f, maxScrollY)
  if state.wordWrap:
    state.scrollPos.x = 0
  else:
    state.scrollPos.x = max(0.0f, state.scrollPos.x)
  let patch =
    if error: "textbox.error.9patch"
    elif not enabled: "textbox.disabled.9patch"
    else: "textbox.9patch"
  let textColor =
    if error: sk.theme.errorTextColor
    elif not enabled: sk.theme.disabledTextColor
    else: sk.theme.textColor
  if state.focused and enabled:
    sk.draw9Patch(patch, 6, outerRect.xy, outerRect.wh,
      sk.theme.frameFocusColor)
  else:
    sk.draw9Patch(patch, 6, outerRect.xy, outerRect.wh)
  sk.pushClipRect(innerRect)
  let textOrigin = innerRect.xy - state.scrollPos
  if state.cursor != state.selector:
    let sel = state.selection
    let selRects = getSelectionRects(state.layout, sel.a, sel.b)
    for r in selRects:
      sk.drawRect(
        vec2(textOrigin.x + r.x, textOrigin.y + r.y),
        vec2(r.w, r.h), SelectionColor)
  discard sk.drawText(
    sk.textStyle,
    state.displayText,
    textOrigin,
    textColor,
    maxWidth = innerRect.w,
    wordWrap = state.wordWrap,
    clip = false
  )
  if state.focused and state.cursorVisible:
    let cr = state.locationRect(state.cursor)
    sk.drawRect(
      vec2(textOrigin.x + cr.x, textOrigin.y + cr.y),
      vec2(CursorWidth, cr.h), textColor)
  sk.popClipRect()
  sk.drawScrollbars(state, window, outerRect, innerRect,
    sk.mousePos, sk.clipRect)
  if sk.mousePos.overlaps(outerRect) and
      sk.mousePos.overlaps(sk.clipRect) and
      window.scrollDelta.y != 0:
    state.scrollBy(
      window.scrollDelta.y * TextBoxScrollSpeed, innerRect.h)
  sk.advance(vec2(boxWidth, boxHeight))

template textBox*(
  id: string,
  t: var string,
  boxWidth, boxHeight: float32,
  wrapWords = true,
  singleLine = false,
  isEnabled = true,
  isError = false,
  isPassword = false,
  passChar: Rune = Rune('*'),
  chars: seq[Rune] = default(seq[Rune])
) =
  ## Text box widget. Set singleLine for a single-line input.
  sk.textBox(window, id, t, boxWidth, boxHeight, wrapWords, singleLine,
    isEnabled, isError, isPassword, passChar, chars
  )

template textInput*(
  id: string,
  t: var string,
  isEnabled: bool = true,
  isError: bool = false,
  chars: seq[Rune] = default(seq[Rune])
) =
  ## Single-line text input widget.
  let itFont = sk.atlas.fonts[sk.textStyle]
  let itHeight = itFont.lineHeight + sk.theme.padding.float32 * 2
  let itWidth = sk.size.x - sk.theme.padding.float32 * 3
  sk.textBox(window, id, t, itWidth, itHeight,
    wrapWords = false, singleLine = true, enabled = isEnabled,
    error = isError, allowedChars = chars)

template passwordInput*(
  id: string,
  t: var string,
  isEnabled: bool = true,
  isError: bool = false,
  passChar: Rune = Rune('*')
) =
  ## Single-line password input widget. Characters are masked.
  let piFont = sk.atlas.fonts[sk.textStyle]
  let piHeight = piFont.lineHeight + sk.theme.padding.float32 * 2
  let piWidth = sk.size.x - sk.theme.padding.float32 * 3
  sk.textBox(
    window,
    id,
    t,
    piWidth,
    piHeight,
    wrapWords = false,
    singleLine = true,
    enabled = isEnabled,
    error = isError,
    password = true,
    passwordChar = passChar
  )
