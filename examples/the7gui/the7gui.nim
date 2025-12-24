
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

const
  BackgroundColor = parseHtmlColor("#000000").rgbx

let sk = newSilky("dist/atlas.png", "dist/atlas.json")

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

proc isValidDate(s: string): bool =
  try:
    discard parse(s, "dd.MM.yyyy")
    return true
  except:
    return false

proc parseDate(s: string): DateTime =
  try:
    return parse(s, "dd.MM.yyyy")
  except:
    # Return a safe default instead of an uninitialized DateTime to avoid crashes
    return dateTime(2000, Month(1), 1, 0, 0, 0, zone = utc())

proc isValidFloat(s: string): bool =
  try:
    discard parseFloat(s)
    return true
  except ValueError:
    return false

window.onFrame = proc() =

  sk.beginUI(window, window.size)

  # Update timer
  let now = epochTime()
  let dt = now - lastFrameTime
  lastFrameTime = now
  timerElapsed = min(timerElapsed + dt, timerDuration)

  # Draw tiled test texture as the background.
  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.at = vec2(x.float32 * 256, y.float32 * 256)
      image("testTexture", rgbx(30, 30, 30, 255))

  subWindow("Challenges", showChallenges, vec2(10, 10), vec2(300, 450)):
    button("Counter"): showCounter = not showCounter
    button("Temperature Converter"): showTemperature = not showTemperature
    button("Flight Booker"): showFlightBooker = not showFlightBooker
    button("Timer"): showTimer = not showTimer
    button("CRUD", false): showCRUD = not showCRUD
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
    inputText(1, celsius, true, not cValid)
    if celsius != oldCelsius:
      try:
        let c = parseFloat(celsius)
        let f = c * (9.0 / 5.0) + 32.0
        fahrenheit = fmt"{f:.1f}"
        if 2 in textInputStates:
           textInputStates[2].setText(fahrenheit)
      except ValueError:
        discard

    let fValid = isValidFloat(fahrenheit)
    let oldFahrenheit = fahrenheit
    text("Fahrenheit")
    inputText(2, fahrenheit, true, not fValid)
    if fahrenheit != oldFahrenheit:
      try:
        let f = parseFloat(fahrenheit)
        let c = (f - 32.0) * (5.0 / 9.0)
        celsius = fmt"{c:.1f}"
        if 1 in textInputStates:
           textInputStates[1].setText(celsius)
      except ValueError:
        discard

  subWindow("Flight Booker", showFlightBooker, vec2(320, 70), vec2(350, 400)):
    dropDown(flightType, ["one-way flight", "return flight"])

    let startValid = isValidDate(startDateStr)
    text("Start Date")
    inputText(3, startDateStr, true, not startValid)

    let isReturn = flightType == "return flight"
    let returnValid = isValidDate(returnDateStr)
    text("Return Date")
    inputText(4, returnDateStr, isReturn, isReturn and not returnValid)

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

  subWindow("CRUD", showCRUD, vec2(150, 150), vec2(400, 300)):
    text("Coming soon...")

  subWindow("Circle Drawer", showCircleDrawer, vec2(160, 160), vec2(400, 400)):
    text("Coming soon...")

  subWindow("Cells", showCells, vec2(170, 170), vec2(500, 400)):
    text("Coming soon...")

  if not showChallenges and not showCounter and not showTemperature and not showFlightBooker and not showTimer and not showCRUD and not showCircleDrawer and not showCells:
    if window.buttonPressed[MouseLeft]:
      showChallenges = true
    sk.at = vec2(100, 100)
    text("Click anywhere to show the Challenges window")

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
