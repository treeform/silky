
import
  std/[strformat, strutils, sequtils],
  bumpy, vmath, chroma,
  silky

type
  SymbolKind = enum
    Operator
    Number

  Symbol = object
    kind: SymbolKind
    number: string
    operator: string

var
  symbols: seq[Symbol] ## List of currently entered symbols.
  repeat: seq[Symbol] ## Used to repeat the previous operation.

proc inNumber() =
  ## Entering a number, make sure everything is setup for it.
  ## It always makes sense to enter in a number.
  if symbols.len == 0 or symbols[^1].kind == Operator:
    symbols.add(Symbol(kind:Number))

proc inOperator(): bool =
  ## Entering operator, make sure everything is setup for it.
  ## Returns true if operator now makes sense.
  if symbols.len == 0:
    return false
  if symbols[^1].kind == Number:
    if symbols[^1].number == "-":
      return false
    symbols.add(Symbol(kind:Operator))
  return true

proc fromFloat(number: float): string =
  ## Formats number as float or integer.
  result = $number
  result.removeSuffix(".0")

proc toFloat(s: string): float =
  ## Parses floats without errors.
  try:
    parseFloat(s)
  except ValueError:
    0

proc compute() =
  ## Compute current symbols and produce an answer (also a symbol).

  if symbols.len > 2:
    # If there are more than 2 symbols remember the last operation.
    repeat = symbols[^2 .. ^1]

  if symbols.len == 0:
    return
  if symbols.len == 1:
    # If there is only 1 symbol, repeat previous operation.
    symbols.add repeat
  if symbols[^1].kind == Operator:
    # Expression is not complete.
    return

  var i: int ## Index into the symbols array.

  proc left(): float =
    ## Grabs the left parameter for the operation.
    toFloat(symbols[i-1].number)

  proc right(): float =
    ## Grabs the right parameter for the operation.
    toFloat(symbols[i+1].number)

  proc operate(number: float) =
    ## Saves the operation back as a symbol.
    symbols[i-1].number = fromFloat(number)
    symbols.delete(i .. i+1)
    dec i

  # Run the symbols, processing × and ÷ first then + and -.
  i = 0
  while i < symbols.len:
    let t = symbols[i]
    if t.operator == "×": operate left() * right()
    if t.operator == "÷": operate left() / right()
    inc i
  i = 0
  while i < symbols.len:
    let t = symbols[i]
    if t.operator == "+": operate left() + right()
    if t.operator == "-": operate left() - right()
    inc i

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
const CalculatorChars = @["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "-", "×", "÷", "±", "%", ".", "=", "C", "a", "l", "c", "u", "l", "a", "t", "o", "r", "f", "m", "e", "i", "s", " ", ":"]
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0, chars = CalculatorChars)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0, chars = CalculatorChars)
builder.write("dist/atlas.png", "dist/atlas.json")

let window = newWindow(
  "Calculator",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const BackgroundColor = parseHtmlColor("#000000").rgbx

let sk = newSilky("dist/atlas.png", "dist/atlas.json")

var showWindow = true

template calcLabel(displayText: string) =
  ## Displays a right-aligned label in a dark background box.
  let
    labelSize = vec2(sk.size.x - 24, 60)
    labelRect = rect(sk.layout.at, labelSize)

  sk.beginWidget("Display", name = "display", text = displayText, rect = labelRect)
  sk.drawRect(sk.layout.at, labelSize, rgbx(50, 50, 50, 255))

  let oldStyle = sk.textStyle
  sk.textStyle = "H1"
  let labelTextSize = sk.getTextSize(sk.textStyle, displayText)
  let textX = sk.layout.at.x + labelSize.x - labelTextSize.x - 10
  discard sk.drawText(sk.textStyle, displayText, vec2(textX, sk.layout.at.y + 14), rgbx(255, 255, 255, 255))
  sk.textStyle = oldStyle
  sk.endWidget()

  sk.advance(vec2(0, 70))

template calcButton(label: string, body: untyped) =
  let
    btnSize = vec2(60, 50)
    startPos = sk.layout.at
    btnRect = rect(startPos, btnSize)

  sk.beginWidget("Button", text = label, rect = btnRect)

  if sk.mouseInsideClip(window, btnRect):
    if window.buttonReleased[MouseLeft]:
      body
    elif window.buttonDown[MouseLeft]:
      sk.draw9Patch("button.down.9patch", 4, startPos, btnSize, rgbx(200, 200, 200, 255))
    else:
      sk.draw9Patch("button.hover.9patch", 4, startPos, btnSize, rgbx(220, 220, 220, 255))
  else:
    sk.draw9Patch("button.9patch", 4, startPos, btnSize)

  let oldStyle = sk.textStyle
  sk.textStyle = "Default"
  let textSize = sk.getTextSize(sk.textStyle, label)
  let textPos = startPos + (btnSize - textSize) / 2
  discard sk.drawText(sk.textStyle, label, textPos, rgbx(255, 255, 255, 255))
  sk.textStyle = oldStyle

  sk.endWidget()

  sk.layout.at.x += btnSize.x + 10
  sk.layout.stretchMax.x = max(sk.layout.stretchMax.x, sk.layout.at.x + 10)
  sk.layout.stretchMax.y = max(sk.layout.stretchMax.y, sk.layout.at.y + 50 + 10)

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.layout.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  subWindow("Calculator", showWindow, vec2(10, 10), vec2(340, 480)):

    # Build the display formula string.
    var formula = ""
    for t in symbols:
      formula.add(t.number)
      formula.add(t.operator)
    formula = formula.replace("--", "+").replace("+-", "-")
    let displayText = if formula == "": "0" else: formula

    # Draw the calculator display.
    calcLabel(displayText)

    let rowX = sk.layout.at.x

    # Row 1: C, +/- (±), %, ÷.
    calcButton("C"):
      if symbols.len > 0:
        repeat.setLen(0)
        symbols.setLen(symbols.len - 1)

    calcButton("±"):
      if symbols.len > 0 and symbols[^1].kind == Number:
        var number = toFloat(symbols[^1].number)
        symbols[^1].number = fromFloat(number / -1)

    calcButton("%"):
      if symbols.len > 0 and symbols[^1].kind == Number:
        var number = toFloat(symbols[^1].number)
        symbols[^1].number = fromFloat(number / 100)

    calcButton("÷"):
      if inOperator(): symbols[^1].operator = "÷"

    sk.layout.at.x = rowX
    sk.layout.at.y += 60

    # Row 2: 7, 8, 9, ×.
    calcButton("7"):
      inNumber()
      symbols[^1].number.add("7")
    calcButton("8"):
      inNumber()
      symbols[^1].number.add("8")
    calcButton("9"):
      inNumber()
      symbols[^1].number.add("9")
    calcButton("×"):
      if inOperator(): symbols[^1].operator = "×"

    sk.layout.at.x = rowX
    sk.layout.at.y += 60

    # Row 3: 4, 5, 6, -.
    calcButton("4"):
      inNumber()
      symbols[^1].number.add("4")
    calcButton("5"):
      inNumber()
      symbols[^1].number.add("5")
    calcButton("6"):
      inNumber()
      symbols[^1].number.add("6")
    calcButton("-"):
      # Minus symbol can be an operator or the start of a negative number.
      if inOperator():
        symbols[^1].operator = "-"
      else:
        inNumber()
        if symbols.len > 0 and symbols[^1].number == "":
          symbols[^1].number = "-"

    sk.layout.at.x = rowX
    sk.layout.at.y += 60

    # Row 4: 1, 2, 3, +.
    calcButton("1"):
      inNumber()
      symbols[^1].number.add("1")
    calcButton("2"):
      inNumber()
      symbols[^1].number.add("2")
    calcButton("3"):
      inNumber()
      symbols[^1].number.add("3")
    calcButton("+"):
      if inOperator(): symbols[^1].operator = "+"

    sk.layout.at.x = rowX
    sk.layout.at.y += 60

    calcButton("0"):
      inNumber()
      symbols[^1].number.add("0")

    calcButton("."):
      inNumber()
      if "." notin symbols[^1].number:
        symbols[^1].number.add(".")

    calcButton("="):
      compute()

    sk.layout.at.x = rowX
    sk.layout.at.y += 60

  if not showWindow:
    if window.buttonPressed[MouseLeft]:
      showWindow = true
    sk.layout.at = vec2(100, 100)

  let ms = sk.avgFrameTime * 1000
  sk.layout.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when isMainModule:
  when defined(emscripten):
    window.run()
  else:
    while not window.closeRequested:
      pollEvents()
