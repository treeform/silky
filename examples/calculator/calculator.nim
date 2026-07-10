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
builder.write("dist/atlas.png")

let window = newWindow(
  "Calculator",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "dist/atlas.png")

var showWindow = true

template calcDisplay(displayText: string) =
  let displayTextSize = sk.getTextSize("H1", displayText)
  rectangle "display":
    box 292, 60
    tint rgbx(50, 50, 50, 255)
    text "display text":
      box max(10.0'f, 282.0'f - displayTextSize.x), 10, displayTextSize.x, 42
      font "H1"
      characters displayText
      tint "#ffffff"

template calcButton(label: string, body: untyped) =
  let buttonTextSize = sk.getTextSize("Default", label)
  rectangle "calc button:" & label:
    box 60, 50
    patch "button.9patch", 4
    onHover:
      patch "button.hover.9patch", 4
      tint rgbx(220, 220, 220, 255)
    onDown:
      patch "button.down.9patch", 4
      tint rgbx(200, 200, 200, 255)
    onClick:
      body
    text "calc label:" & label:
      box (60.0'f - buttonTextSize.x) * 0.5, 13, buttonTextSize.x, 24
      characters label
      tint "#ffffff"

template calcRow(id: string, body: untyped) =
  group "row:" & id:
    box 292, 54
    layout LeftToRight
    itemSpacing 10
    body

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(rgbx(30, 30, 30, 255))

  ui:
    subWindow("Calculator", showWindow, vec2(10, 10), vec2(340, 480)):
      var formula = ""
      for t in symbols:
        formula.add(t.number)
        formula.add(t.operator)
      formula = formula.replace("--", "+").replace("+-", "-")
      let displayText = if formula == "": "0" else: formula

      calcDisplay displayText

      calcRow "ops":
        calcButton "C":
          if symbols.len > 0:
            repeat.setLen(0)
            symbols.setLen(symbols.len - 1)
        calcButton "±":
          if symbols.len > 0 and symbols[^1].kind == Number:
            let number = toFloat(symbols[^1].number)
            symbols[^1].number = fromFloat(number / -1)
        calcButton "%":
          if symbols.len > 0 and symbols[^1].kind == Number:
            let number = toFloat(symbols[^1].number)
            symbols[^1].number = fromFloat(number / 100)
        calcButton "÷":
          if inOperator(): symbols[^1].operator = "÷"

      calcRow "789":
        calcButton "7":
          inNumber()
          symbols[^1].number.add("7")
        calcButton "8":
          inNumber()
          symbols[^1].number.add("8")
        calcButton "9":
          inNumber()
          symbols[^1].number.add("9")
        calcButton "×":
          if inOperator(): symbols[^1].operator = "×"

      calcRow "456":
        calcButton "4":
          inNumber()
          symbols[^1].number.add("4")
        calcButton "5":
          inNumber()
          symbols[^1].number.add("5")
        calcButton "6":
          inNumber()
          symbols[^1].number.add("6")
        calcButton "-":
          if inOperator():
            symbols[^1].operator = "-"
          else:
            inNumber()
            if symbols.len > 0 and symbols[^1].number == "":
              symbols[^1].number = "-"

      calcRow "123":
        calcButton "1":
          inNumber()
          symbols[^1].number.add("1")
        calcButton "2":
          inNumber()
          symbols[^1].number.add("2")
        calcButton "3":
          inNumber()
          symbols[^1].number.add("3")
        calcButton "+":
          if inOperator(): symbols[^1].operator = "+"

      calcRow "0":
        calcButton "0":
          inNumber()
          symbols[^1].number.add("0")
        calcButton ".":
          inNumber()
          if "." notin symbols[^1].number:
            symbols[^1].number.add(".")
        calcButton "=":
          compute()

    if not showWindow:
      if window.buttonPressed[MouseLeft]:
        showWindow = true

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
