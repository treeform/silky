
import
  std/[strformat, strutils, times],
  opengl, windy, bumpy, vmath, chroma,
  silky

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png", "dist/atlas.json")

let window = newWindow(
  "7GUIs - Counter",
  ivec2(800, 600),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

const BackgroundColor = parseHtmlColor("#000000").rgbx

let sk = newSilky("dist/atlas.png", "dist/atlas.json")

# Set up a light theme for 7GUIs.
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
  ## Check if the string is a valid date.
  try:
    discard parse(s, "dd.MM.yyyy")
    return true
  except:
    return false

proc parseDate(s: string): DateTime =
  ## Parse a date string or return a safe default on failure.
  try:
    return parse(s, "dd.MM.yyyy")
  except:
    return dateTime(2000, Month(1), 1, 0, 0, 0, zone = utc())

proc isValidFloat(s: string): bool =
  ## Check if the string is a valid float.
  try:
    discard parseFloat(s)
    return true
  except ValueError:
    return false

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Update the timer elapsed time.
  let now = epochTime()
  let dt = now - lastFrameTime
  lastFrameTime = now
  timerElapsed = min(timerElapsed + dt, timerDuration)

  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.layout.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  subWindow("Challenges", showChallenges, vec2(10, 10), vec2(300, 450)):
    button("Counter"): showCounter = not showCounter
    button("Temperature Converter"): showTemperature = not showTemperature
    button("Flight Booker"): showFlightBooker = not showFlightBooker
    button("Timer"): showTimer = not showTimer
    button("CRUD"): showCRUD = not showCRUD
    button("Circle Drawer", false): showCircleDrawer = not showCircleDrawer
    button("Cells", false): showCells = not showCells

  subWindow("Counter", showCounter, vec2(320, 50), vec2(320, 200)):
    text(&"{counter}")
    button("Count"):
      inc counter

  subWindow("Temperature Converter", showTemperature, vec2(320, 60), vec2(320, 250)):
    let cValid = isValidFloat(celsius)
    let oldCelsius = celsius
    text("Celsius")
    textInput("celsius", celsius, true, not cValid)
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
    text("Fahrenheit")
    textInput("fahrenheit", fahrenheit, true, not fValid)
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
    dropDown(flightType, ["one-way flight", "return flight"])

    let startValid = isValidDate(startDateStr)
    text("Start Date")
    textInput("startDate", startDateStr, true, not startValid)

    let isReturn = flightType == "return flight"
    let returnValid = isValidDate(returnDateStr)
    text("Return Date")
    textInput("returnDate", returnDateStr, isReturn, isReturn and not returnValid)

    var dateOrderError = false
    if isReturn and startValid and returnValid:
      let start = parseDate(startDateStr)
      let ret = parseDate(returnDateStr)
      if ret < start:
        dateOrderError = true

    var canBook = startValid and (not isReturn or (returnValid and not dateOrderError))

    button("Book", canBook, dateOrderError):
      if flightType == "one-way flight":
        bookedMessage = &"You have booked a one-way flight on {startDateStr}."
      else:
        bookedMessage = &"You have booked a return flight departing on {startDateStr} and returning on {returnDateStr}."

    if dateOrderError:
      text("Return date cannot be before start date.")
    elif bookedMessage != "":
      text(bookedMessage)

  subWindow("Timer", showTimer, vec2(320, 80), vec2(300, 250)):
    text(&"Elapsed Time: {timerElapsed:.1f}s")
    progressBar(timerElapsed, 0, timerDuration)
    text("Duration:")
    scrubber("timer_scrubber", timerDuration, 0.1, 60.0)
    button("Reset"):
      timerElapsed = 0.0

  subWindow("CRUD", showCRUD, vec2(150, 150), vec2(400, 450)):
    text("Filter prefix:")
    textInput("crudPrefix", crudPrefix)

    # Filter database based on prefix using case insensitive comparison.
    var filteredItems: seq[string]
    var originalIndices: seq[int]
    for i, person in crudDatabase:
      if crudPrefix == "" or person.toLowerAscii().startsWith(crudPrefix.toLowerAscii()):
        filteredItems.add(person)
        originalIndices.add(i)

    # If selection is out of bounds for the filtered list, reset it.
    if crudSelected >= filteredItems.len:
      crudSelected = -1

    listBox("crud_list", filteredItems, crudSelected)

    # If selection changed, sync the name and surname fields.
    if crudSelected != oldCrudSelected:
      if crudSelected != -1 and crudSelected < filteredItems.len:
        let person = filteredItems[crudSelected]
        let parts = person.split(", ")
        if parts.len == 2:
          crudSurname = parts[0]
          crudName = parts[1]
      else:
        # Clear fields when selection is lost.
        crudName = ""
        crudSurname = ""

      # Sync back to input text states to update display immediately.
      if "crudName" in textBoxStates: textBoxStates["crudName"].setText(crudName)
      if "crudSurname" in textBoxStates: textBoxStates["crudSurname"].setText(crudSurname)
      oldCrudSelected = crudSelected

    text("Name:")
    textInput("crudName", crudName)
    text("Surname:")
    textInput("crudSurname", crudSurname)

    let canUpdateDelete = crudSelected != -1
    let originalIdx = if canUpdateDelete: originalIndices[crudSelected] else: -1

    group(vec2(0, 0), LeftToRight):
      button("Create"):
        if crudName != "" and crudSurname != "":
          crudDatabase.add(crudSurname & ", " & crudName)
          crudName = ""
          crudSurname = ""

      button("Update", canUpdateDelete):
        if crudName != "" and crudSurname != "":
          crudDatabase[originalIdx] = crudSurname & ", " & crudName

      button("Delete", canUpdateDelete):
        crudDatabase.delete(originalIdx)
        crudSelected = -1
        crudName = ""
        crudSurname = ""
        if "crudName" in textBoxStates: textBoxStates["crudName"].setText("")
        if "crudSurname" in textBoxStates: textBoxStates["crudSurname"].setText("")

  subWindow("Circle Drawer", showCircleDrawer, vec2(160, 160), vec2(400, 400)):
    text("Coming soon...")

  subWindow("Cells", showCells, vec2(170, 170), vec2(500, 400)):
    text("Coming soon...")

  if not showChallenges and not showCounter and not showTemperature and not showFlightBooker and not showTimer and not showCRUD and not showCircleDrawer and not showCells:
    if window.buttonPressed[MouseLeft]:
      showChallenges = true
    sk.layout.at = vec2(100, 100)
    text("Click anywhere to show the Challenges window")

  let ms = sk.avgFrameTime * 1000
  sk.layout.at = sk.pos + vec2(sk.size.x - 250, 20)
  text(&"frame time: {ms:>7.3f}ms")

  sk.endUi()
  window.swapBuffers()

when defined(emscripten):
  window.run()
else:
  while not window.closeRequested:
    pollEvents()
