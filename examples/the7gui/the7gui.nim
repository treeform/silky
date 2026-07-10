import
  std/[strformat, strutils, times],
  bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "7GUIs",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "dist/atlas.png")

sk.theme.defaultTextColor = parseHtmlColor("#2C3E50").rgbx
sk.theme.disabledTextColor = parseHtmlColor("#95A5A6").rgbx
sk.theme.errorTextColor = parseHtmlColor("#E74C3C").rgbx
sk.theme.textColor = parseHtmlColor("#2C3E50").rgbx
sk.theme.textH1Color = parseHtmlColor("#1A252F").rgbx
sk.theme.frameFocusColor = parseHtmlColor("#D5DBDB").rgbx
sk.theme.dropdownBgColor = parseHtmlColor("#ECF0F1").rgbx
sk.theme.dropdownHoverBgColor = parseHtmlColor("#BDC3C7").rgbx
sk.theme.dropdownPopupBgColor = parseHtmlColor("#FDFEFE").rgbx
sk.theme.buttonHoverColor = rgbx(200, 200, 200, 255)
sk.theme.buttonDownColor = rgbx(180, 180, 180, 255)
sk.theme.menuPopupHoverColor = parseHtmlColor("#3498DB").rgbx
sk.theme.menuPopupSelectedColor = parseHtmlColor("#2980B9").rgbx

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

var
  showChallenges = true
  showCounter = false
  showTemperature = false
  showFlightBooker = false
  showTimer = false
  showCRUD = false
  showCircleDrawer = false
  showCells = false

  counter = 0
  celsius = "0"
  fahrenheit = "32"
  flightType = "one-way flight"
  startDateStr = "24.12.2025"
  returnDateStr = "24.12.2025"
  bookedMessage = ""

  timerDuration = 10.0
  timerElapsed = 0.0
  lastFrameTime = epochTime()

  crudPrefix = ""
  crudName = ""
  crudSurname = ""
  crudDatabase = @["Emil, Hans", "Mustermann, Max", "Tisch, Roman"]
  crudSelected = -1
  oldCrudSelected = -1

proc isValidDate(s: string): bool =
  try:
    discard parse(s, "dd.MM.yyyy")
    true
  except:
    false

proc parseDate(s: string): DateTime =
  try:
    parse(s, "dd.MM.yyyy")
  except:
    dateTime(2000, Month(1), 1, 0, 0, 0, zone = utc())

proc isValidFloat(s: string): bool =
  try:
    discard parseFloat(s)
    true
  except ValueError:
    false

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(rgbx(30, 30, 30, 255))

  let now = epochTime()
  let dt = now - lastFrameTime
  lastFrameTime = now
  timerElapsed = min(timerElapsed + dt, timerDuration)

  ui:
    subWindow("Challenges", showChallenges, vec2(10, 10), vec2(300, 450)):
      button "Counter":
        showCounter = not showCounter
      button "Temperature Converter":
        showTemperature = not showTemperature
      button "Flight Booker":
        showFlightBooker = not showFlightBooker
      button "Timer":
        showTimer = not showTimer
      button "CRUD":
        showCRUD = not showCRUD
      button "Circle Drawer", false:
        showCircleDrawer = not showCircleDrawer
      button "Cells", false:
        showCells = not showCells

    subWindow("Counter", showCounter, vec2(320, 50), vec2(320, 200)):
      text "counter value":
        characters &"{counter}"
      button "Count":
        inc counter

    subWindow("Temperature Converter", showTemperature, vec2(320, 60), vec2(320, 250)):
      let cValid = isValidFloat(celsius)
      let oldCelsius = celsius
      text "celsius label":
        characters "Celsius"
      textInput "celsius", celsius, true, not cValid
      if celsius != oldCelsius:
        try:
          let c = parseFloat(celsius)
          let f = c * (9.0 / 5.0) + 32.0
          fahrenheit = fmt"{f:.1f}"
          if "fahrenheit" in textBoxStates:
             textBoxStates["fahrenheit"].setText(fahrenheit)
        except ValueError:
          discard

      let fValid = isValidFloat(fahrenheit)
      let oldFahrenheit = fahrenheit
      text "fahrenheit label":
        characters "Fahrenheit"
      textInput "fahrenheit", fahrenheit, true, not fValid
      if fahrenheit != oldFahrenheit:
        try:
          let f = parseFloat(fahrenheit)
          let c = (f - 32.0) * (5.0 / 9.0)
          celsius = fmt"{c:.1f}"
          if "celsius" in textBoxStates:
             textBoxStates["celsius"].setText(celsius)
        except ValueError:
          discard

    subWindow("Flight Booker", showFlightBooker, vec2(320, 70), vec2(350, 400)):
      dropDown flightType, ["one-way flight", "return flight"]

      let startValid = isValidDate(startDateStr)
      text "start label":
        characters "Start Date"
      textInput "startDate", startDateStr, true, not startValid

      let isReturn = flightType == "return flight"
      let returnValid = isValidDate(returnDateStr)
      text "return label":
        characters "Return Date"
      textInput "returnDate", returnDateStr, isReturn, isReturn and not returnValid

      var dateOrderError = false
      if isReturn and startValid and returnValid:
        let start = parseDate(startDateStr)
        let ret = parseDate(returnDateStr)
        if ret < start:
          dateOrderError = true

      let canBook = startValid and (not isReturn or (returnValid and not dateOrderError))

      button "Book", canBook, dateOrderError:
        if flightType == "one-way flight":
          bookedMessage = &"You have booked a one-way flight on {startDateStr}."
        else:
          bookedMessage = &"You have booked a return flight departing on {startDateStr} and returning on {returnDateStr}."

      if dateOrderError:
        text "date order error":
          characters "Return date cannot be before start date."
      elif bookedMessage != "":
        text "booked message":
          characters bookedMessage

    subWindow("Timer", showTimer, vec2(320, 80), vec2(300, 250)):
      text "elapsed":
        characters &"Elapsed Time: {timerElapsed:.1f}s"
      progressBar timerElapsed, 0, timerDuration
      text "duration label":
        characters "Duration:"
      scrubber "timer_scrubber", timerDuration, 0.1, 60.0
      button "Reset":
        timerElapsed = 0.0

    subWindow("CRUD", showCRUD, vec2(150, 150), vec2(400, 450)):
      text "filter label":
        characters "Filter prefix:"
      textInput "crudPrefix", crudPrefix

      var filteredItems: seq[string]
      var originalIndices: seq[int]
      for i, person in crudDatabase:
        if crudPrefix == "" or person.toLowerAscii().startsWith(crudPrefix.toLowerAscii()):
          filteredItems.add(person)
          originalIndices.add(i)

      if crudSelected >= filteredItems.len:
        crudSelected = -1

      listBox "crud_list", filteredItems, crudSelected

      if crudSelected != oldCrudSelected:
        if crudSelected != -1 and crudSelected < filteredItems.len:
          let person = filteredItems[crudSelected]
          let parts = person.split(", ")
          if parts.len == 2:
            crudSurname = parts[0]
            crudName = parts[1]
        else:
          crudName = ""
          crudSurname = ""

        if "crudName" in textBoxStates: textBoxStates["crudName"].setText(crudName)
        if "crudSurname" in textBoxStates: textBoxStates["crudSurname"].setText(crudSurname)
        oldCrudSelected = crudSelected

      text "name label":
        characters "Name:"
      textInput "crudName", crudName
      text "surname label":
        characters "Surname:"
      textInput "crudSurname", crudSurname

      let canUpdateDelete = crudSelected != -1
      let originalIdx = if canUpdateDelete: originalIndices[crudSelected] else: -1

      group "crud actions":
        box 340, 42
        layout LeftToRight
        itemSpacing 8
        button "Create":
          if crudName != "" and crudSurname != "":
            crudDatabase.add(crudSurname & ", " & crudName)
            crudName = ""
            crudSurname = ""

        button "Update", canUpdateDelete:
          if crudName != "" and crudSurname != "":
            crudDatabase[originalIdx] = crudSurname & ", " & crudName

        button "Delete", canUpdateDelete:
          crudDatabase.delete(originalIdx)
          crudSelected = -1
          crudName = ""
          crudSurname = ""
          if "crudName" in textBoxStates: textBoxStates["crudName"].setText("")
          if "crudSurname" in textBoxStates: textBoxStates["crudSurname"].setText("")

    subWindow("Circle Drawer", showCircleDrawer, vec2(160, 160), vec2(400, 400)):
      text "circle soon":
        characters "Coming soon..."

    subWindow("Cells", showCells, vec2(170, 170), vec2(500, 400)):
      text "cells soon":
        characters "Coming soon..."

    if not showChallenges and not showCounter and not showTemperature and
        not showFlightBooker and not showTimer and not showCRUD and
        not showCircleDrawer and not showCells:
      text "restore prompt":
        box 100, 100, 440, 28
        characters "Click anywhere to show the Challenges window"
      if window.buttonPressed[MouseLeft]:
        showChallenges = true

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
