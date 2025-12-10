
import
  std/[strformat, strutils, sequtils],
  opengl, windy, bumpy, vmath, chroma,
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
  repeat: seq[Symbol] ## Used to repeat prev operation

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
    # If there is more then 2 symbols remember the last operation.
    repeat = symbols[^2 .. ^1]

  if symbols.len == 0:
    return
  if symbols.len == 1:
    # If there is only 1 symbol, repeat previous operation.
    symbols.add repeat
  if symbols[^1].kind == Operator:
    # Not complete.
    return

  var i: int # Used to count where we are in the symbols array.

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

  # Runs the symbols, × and ÷ first then + and -.
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
const calculatorChars = @["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "-", "×", "÷", "±", "%", ".", "=", "C"]
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0, chars = calculatorChars)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0, chars = calculatorChars)
builder.write("dist/atlas.png", "dist/atlas.json")

let window = newWindow(
  "Calculator",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const
  BackgroundColor = parseHtmlColor("#000000").rgbx

let sk = newSilky("dist/atlas.png", "dist/atlas.json")

var
  showWindow = true

template calcButton(label: string, body: untyped) =
  let
    btnSize = vec2(60, 50)
    startPos = sk.at

  if sk.layer == sk.topLayer and window.mousePos.vec2.overlaps(rect(startPos, btnSize)):
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

  sk.at.x += btnSize.x + 10

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  subWindow("Calculator", showWindow):

    # Display
    var formula = ""
    for t in symbols:
      formula.add(t.number)
      formula.add(t.operator)
    formula = formula.replace("--", "+").replace("+-", "-")

    # Draw display background
    sk.drawRect(sk.at, vec2(sk.size.x - 24, 60), rgbx(50, 50, 50, 255))

    # Right align text? Or just left for now.
    # Text
    let oldStyle = sk.textStyle
    sk.textStyle = "H1"
    let displayText = if formula == "": "0" else: formula
    let textSize = sk.getTextSize(sk.textStyle, displayText)
    # Right align
    let textX = sk.at.x + (sk.size.x - 24) - textSize.x - 10
    discard sk.drawText(sk.textStyle, displayText, vec2(textX, sk.at.y + 14), rgbx(255, 255, 255, 255))
    sk.textStyle = oldStyle

    sk.advance(vec2(0, 70)) # Move past display

    let rowX = sk.at.x

    # Row 1: C, +/- (±), %, ÷
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

    sk.at.x = rowX
    sk.at.y += 60

    # Row 2: 7, 8, 9, ×
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

    sk.at.x = rowX
    sk.at.y += 60

    # Row 3: 4, 5, 6, -
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
      # Minus symbol can be an operator or start of a number
      if inOperator():
        symbols[^1].operator = "-"
      else:
        inNumber()
        if symbols.len > 0 and symbols[^1].number == "":
          symbols[^1].number = "-"

    sk.at.x = rowX
    sk.at.y += 60

    # Row 4: 1, 2, 3, +
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

    sk.at.x = rowX
    sk.at.y += 60

    # Row 5: 0, ., =
    # 0 button double width? Or just regular. Fidget example uses "Button0".
    # I'll make it regular for grid consistency or custom width.
    # calcButton("0") ...
    # But usually 0 is wide. I'll stick to regular for now to fit the template.
    calcButton("0"):
      inNumber()
      symbols[^1].number.add("0")

    calcButton("."):
      inNumber()
      if "." notin symbols[^1].number:
        symbols[^1].number.add(".")

    calcButton("="):
      compute()

    # Empty spot or maybe backspace? Fidget doesn't have it.

    sk.at.x = rowX
    sk.at.y += 60

  if not showWindow:
    if window.buttonPressed[MouseLeft]:
      showWindow = true
    sk.at = vec2(100, 100)
    text("Click anywhere to show the calculator")

  let ms = sk.avgFrameTime * 1000
  sk.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
