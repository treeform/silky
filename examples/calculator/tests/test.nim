## Calculator UI tests using semantic capture.
## Run with: nim r tests/test.nim (from calculator folder)

when not defined(silkyTesting):
  {.error: "Must compile with -d:silkyTesting".}

import
  std/unittest,
  silky,
  ../calculator {.all.}

proc resetCalculator() =
  ## Resets calculator state to initial values.
  symbols.setLen(0)
  calculator.repeat.setLen(0)
  showWindow = true

proc getDisplay(): string =
  ## Reads the display text from the UI semantic tree.
  window.pumpFrame(sk)
  let display = sk.semantic.root.findByName("display text", "Text")
  if display != nil:
    return display.text
  return "0"

proc clickCalc(label: string) =
  ## Clicks a calculator key by its label text node.
  window.clickText(sk, label, "Text")

suite "Calculator UI - Initial State":

  setup:
    resetCalculator()
    window.pumpFrame(sk)

  test "all digit buttons present":
    for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
      let btn = sk.semantic.root.findByText(digit, "Text")
      check btn != nil
      check btn.rect.w > 0
      check btn.rect.h > 0

  test "all operator buttons present":
    for op in ["+", "-", "×", "÷", "=", "C", "±", "%", "."]:
      let btn = sk.semantic.root.findByText(op, "Text")
      check btn != nil
      check btn.rect.w > 0

  test "display shows 0 initially":
    let display = sk.semantic.root.findByName("display text", "Text")
    check display != nil
    check display.text == "0"
    check display.rect.w > 0
    check display.rect.h > 0

  test "calculator SubWindow present":
    let win = sk.semantic.root.findByName("Calculator", "SubWindow")
    check win != nil
    check win.rect.w > 0
    check win.rect.h > 0

suite "Calculator UI - Basic Arithmetic":

  setup:
    resetCalculator()

  test "simple addition (7 + 3 = 10)":
    clickCalc("7")
    check getDisplay() == "7"
    clickCalc("+")
    check getDisplay() == "7+"
    clickCalc("3")
    check getDisplay() == "7+3"
    clickCalc("=")
    check getDisplay() == "10"

  test "multiplication (6 × 7 = 42)":
    clickCalc("6")
    clickCalc("×")
    clickCalc("7")
    check getDisplay() == "6×7"
    clickCalc("=")
    check getDisplay() == "42"

  test "division (84 ÷ 2 = 42)":
    clickCalc("8")
    clickCalc("4")
    clickCalc("÷")
    clickCalc("2")
    check getDisplay() == "84÷2"
    clickCalc("=")
    check getDisplay() == "42"

  test "subtraction (100 - 58 = 42)":
    clickCalc("1")
    clickCalc("0")
    clickCalc("0")
    clickCalc("-")
    clickCalc("5")
    clickCalc("8")
    check getDisplay() == "100-58"
    clickCalc("=")
    check getDisplay() == "42"

  test "negative result (5 - 10 = -5)":
    clickCalc("5")
    clickCalc("-")
    clickCalc("1")
    clickCalc("0")
    check getDisplay() == "5-10"
    clickCalc("=")
    check getDisplay() == "-5"

  test "decimal numbers (3.14 + 2.86 = 6)":
    clickCalc("3")
    clickCalc(".")
    clickCalc("1")
    clickCalc("4")
    clickCalc("+")
    clickCalc("2")
    clickCalc(".")
    clickCalc("8")
    clickCalc("6")
    check getDisplay() == "3.14+2.86"
    clickCalc("=")
    check getDisplay() == "6"

suite "Calculator UI - Order of Operations":

  setup:
    resetCalculator()

  test "multiplication before addition (2 + 3 × 4 = 14)":
    clickCalc("2")
    clickCalc("+")
    clickCalc("3")
    clickCalc("×")
    clickCalc("4")
    check getDisplay() == "2+3×4"
    clickCalc("=")
    check getDisplay() == "14"

  test "chained operations (10 + 5 × 2 - 4 = 16)":
    clickCalc("1")
    clickCalc("0")
    clickCalc("+")
    clickCalc("5")
    clickCalc("×")
    clickCalc("2")
    clickCalc("-")
    clickCalc("4")
    check getDisplay() == "10+5×2-4"
    clickCalc("=")
    check getDisplay() == "16"

suite "Calculator UI - Clear Button":

  setup:
    resetCalculator()

  test "clear removes symbols one at a time":
    clickCalc("5")
    clickCalc("+")
    clickCalc("3")
    check getDisplay() == "5+3"

    clickCalc("C")
    check getDisplay() == "5+"

    clickCalc("C")
    check getDisplay() == "5"

    clickCalc("C")
    check getDisplay() == "0"

  test "clear on empty display stays at 0":
    check getDisplay() == "0"
    clickCalc("C")
    check getDisplay() == "0"

  test "can enter new expression after clear":
    clickCalc("9")
    clickCalc("+")
    clickCalc("1")
    clickCalc("C")
    clickCalc("C")
    clickCalc("C")
    check getDisplay() == "0"

    clickCalc("4")
    clickCalc("2")
    check getDisplay() == "42"

suite "Calculator UI - Display State":

  setup:
    resetCalculator()

  test "display node updates text after each button":
    clickCalc("1")
    window.pumpFrame(sk)
    let
      d1 = sk.semantic.root.findByName("display text", "Text")
    check d1 != nil
    check d1.text == "1"

    clickCalc("2")
    window.pumpFrame(sk)
    let d2 = sk.semantic.root.findByName("display text", "Text")
    check d2.text == "12"

  test "display resets after equals then new input":
    clickCalc("5")
    clickCalc("+")
    clickCalc("3")
    clickCalc("=")
    check getDisplay() == "8"

    clickCalc("1")
    check getDisplay() == "81"
