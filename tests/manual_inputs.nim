import
  std/math,
  chroma, vmath, bumpy,
  silky

const
  Margin = 20.0'f
  Gap = 20.0'f
  LeftWidth = 300.0'f
  Background = rgbx(26, 30, 38, 255)
  KeyHeight = 36.0'f
  KeyGap = 4.0'f
  Keyboard = [
    @[("`", KeyBacktick, 1.0'f), ("1", Key1, 1.0'f),
      ("2", Key2, 1.0'f), ("3", Key3, 1.0'f), ("4", Key4, 1.0'f),
      ("5", Key5, 1.0'f), ("6", Key6, 1.0'f), ("7", Key7, 1.0'f),
      ("8", Key8, 1.0'f), ("9", Key9, 1.0'f), ("0", Key0, 1.0'f),
      ("-", KeyMinus, 1.0'f), ("=", KeyEqual, 1.0'f),
      ("Back", KeyBackspace, 2.0'f)],
    @[("Tab", KeyTab, 1.5'f), ("Q", KeyQ, 1.0'f), ("W", KeyW, 1.0'f),
      ("E", KeyE, 1.0'f), ("R", KeyR, 1.0'f), ("T", KeyT, 1.0'f),
      ("Y", KeyY, 1.0'f), ("U", KeyU, 1.0'f), ("I", KeyI, 1.0'f),
      ("O", KeyO, 1.0'f), ("P", KeyP, 1.0'f),
      ("[", KeyLeftBracket, 1.0'f), ("]", KeyRightBracket, 1.0'f),
      ("\\", KeyBackslash, 1.5'f)],
    @[("Caps", KeyCapsLock, 1.75'f), ("A", KeyA, 1.0'f),
      ("S", KeyS, 1.0'f), ("D", KeyD, 1.0'f), ("F", KeyF, 1.0'f),
      ("G", KeyG, 1.0'f), ("H", KeyH, 1.0'f), ("J", KeyJ, 1.0'f),
      ("K", KeyK, 1.0'f), ("L", KeyL, 1.0'f),
      (";", KeySemicolon, 1.0'f), ("'", KeyApostrophe, 1.0'f),
      ("Enter", KeyEnter, 2.25'f)],
    @[("Shift", KeyLeftShift, 2.25'f), ("Z", KeyZ, 1.0'f),
      ("X", KeyX, 1.0'f), ("C", KeyC, 1.0'f), ("V", KeyV, 1.0'f),
      ("B", KeyB, 1.0'f), ("N", KeyN, 1.0'f), ("M", KeyM, 1.0'f),
      (",", KeyComma, 1.0'f), (".", KeyPeriod, 1.0'f),
      ("/", KeySlash, 1.0'f), ("Shift", KeyRightShift, 2.75'f)],
    @[("Ctrl", KeyLeftControl, 1.25'f),
      ("Super", KeyLeftSuper, 1.25'f), ("Alt", KeyLeftAlt, 1.25'f),
      ("Space", KeySpace, 6.25'f), ("Alt", KeyRightAlt, 1.25'f),
      ("Super", KeyRightSuper, 1.25'f), ("Menu", KeyMenu, 1.25'f),
      ("Ctrl", KeyRightControl, 1.25'f)]
  ]

proc drawKeyboard(sk: Silky, y, lineHeight: float32) =
  ## Draws staggered QWERTY rows using the same key state as game controls.
  discard sk.drawText(
    "Default",
    "Click outside the fields, then hold keys. Typing keeps these keys dark.",
    vec2(Margin, y),
    sk.theme.textColor
  )
  let
    unit = min(60.0'f, max(0.0'f, sk.size.x - Margin * 2) / 15)
    keys = sk.buttonDown
  for rowIndex, row in Keyboard:
    var x = Margin
    for (label, button, units) in row:
      let
        width = unit * units - KeyGap
        pos = vec2(x, y + lineHeight + 8 + rowIndex.float32 * KeyHeight)
        color =
          if keys[button]:
            rgbx(65, 150, 220, 255)
          else:
            rgbx(48, 55, 66, 255)
        textSize = sk.getTextSize("Default", label)
      sk.drawRect(pos, vec2(max(0.0'f, width), KeyHeight - KeyGap), color)
      if width >= textSize.x:
        discard sk.drawText(
          "Default",
          label,
          pos + vec2((width - textSize.x) / 2, 3),
          sk.theme.textColor
        )
      x += unit * units

proc main() =
  ## Displays four text fields for shortcut, selection, and resize checks.
  let builder = newAtlasBuilder(1024, 4)
  builder.addDir("tests/data/", "tests/data/")
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18.0)
  let
    font = builder.atlas.fonts["Default"]
    padding = Theme().padding.float32
    lineHeight = font.lineHeight
    labelHeight = lineHeight + 8
    headerHeight = lineHeight + Gap
    keyboardHeight = labelHeight + KeyHeight * Keyboard.len.float32
  var glyph: ptr LetterEntry
  doAssert font.lookupLetter(Rune('0'), 0, glyph)
  let
    editorWidth = glyph.advance * 60 + padding * 2
    editorHeight = lineHeight * 20 + padding * 2
    window = newWindow(
      "Silky Text Inputs",
      ivec2(
        ceil(Margin * 2 + LeftWidth + Gap + editorWidth).int32,
        ceil(Margin * 2 + headerHeight + labelHeight + editorHeight +
          Gap + keyboardHeight).int32
      )
    )
  window.makeContextCurrent()
  loadExtensions()
  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  var
    name = "Hello"
    password = "secret"
    notes = "First line\nSecond line\nThird line"
    document = "Try quick Command-A or Ctrl-A, then type a replacement.\n\n"
  for i in 1 .. 30:
    document.add("Line " & $i & ": Edit, select, and scroll this text.\n")

  window.onFrame = proc() =
    sk.beginUi(window, window.size)
    sk.clearScreen(Background)
    let
      availableWidth = max(0.0'f, sk.size.x - Margin * 2 - Gap)
      leftWidth = min(LeftWidth, availableWidth * 0.35'f)
      rightX = Margin + leftWidth + Gap
      top = Margin + headerHeight
      rightWidth = max(0.0'f, sk.size.x - rightX - Margin)
      keyboardY = max(top, sk.size.y - Margin - keyboardHeight)
      rightHeight = max(0.0'f, keyboardY - Gap - top - labelHeight)
      singleHeight = lineHeight + padding * 2
    discard sk.drawText(
      "Default",
      "Click a field. Try Ctrl/Cmd+A, then type. Resize the window.",
      vec2(Margin, Margin),
      sk.theme.textColor
    )

    proc field(
      id, label: string,
      value: var string,
      x, y, width, height: float32,
      singleLine = false,
      password = false
    ) =
      ## Draws a labeled input with explicit viewport dimensions.
      if y + labelHeight >= keyboardY - Gap or width <= 0 or height <= 0:
        return
      discard sk.drawText(
        "Default",
        label,
        vec2(x, y),
        sk.theme.textColor
      )
      sk.at = vec2(x, y + labelHeight)
      sk.textBox(
        window,
        id,
        value,
        width,
        height,
        wrapWords = not singleLine,
        singleLine = singleLine,
        password = password
      )

    sk.pushClipRect(rect(
      Margin,
      top,
      max(0.0'f, sk.size.x - Margin * 2),
      max(0.0'f, keyboardY - Gap - top)
    ))
    field(
      "name",
      "Single line",
      name,
      Margin,
      top,
      leftWidth,
      singleHeight,
      singleLine = true
    )
    field(
      "password",
      "Password",
      password,
      Margin,
      top + labelHeight + singleHeight + Gap,
      leftWidth,
      singleHeight,
      singleLine = true,
      password = true
    )
    field(
      "notes",
      "Three lines",
      notes,
      Margin,
      top + (labelHeight + singleHeight + Gap) * 2,
      leftWidth,
      lineHeight * 3 + padding * 2
    )
    field(
      "document",
      "Editor",
      document,
      rightX,
      top,
      rightWidth,
      rightHeight
    )
    sk.popClipRect()
    sk.drawKeyboard(keyboardY, lineHeight)
    sk.endUi()
    window.swapBuffers()

  while not window.closeRequested:
    pollEvents()
  window.close()

main()
