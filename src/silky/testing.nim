## Test harness for Silky UI testing without a real window or GPU.

import std/unicode
import vmath, bumpy
import silky/[semantic, atlas]
from windy/common import Button, CursorKind, Cursor

export Button, CursorKind, Cursor, unicode

type
  Window* = ref object
    ## Test window that simulates a windy Window.
    size*: IVec2
    mousePrevPos*: IVec2
    mousePos*: IVec2
    mouseDelta*: IVec2
    buttonDown*: array[Button, bool]
    buttonPressed*: array[Button, bool]
    buttonReleased*: array[Button, bool]
    scrollDelta*: Vec2
    ## Starts true so `while not window.closeRequested` loops exit immediately in tests.
    closeRequested*: bool = true
    cursor*: Cursor = Cursor(kind: ArrowCursor)
    runeInputEnabled*: bool
    onRune*: proc(rune: Rune)
    onFrame*: proc()

  TestHarness* = object
    ## Test harness for running Silky UI tests.
    sk*: Silky
    window*: Window
    lastSnapshot*: string
    frameCount*: int

proc newWindow*(width = 800, height = 600): Window =
  ## Creates a new test window with the given dimensions.
  Window(
    size: ivec2(width.int32, height.int32),
    mousePrevPos: ivec2(0, 0),
    mouseDelta: ivec2(0, 0),
    mousePos: ivec2(0, 0)
  )

proc newWindow*(title: string, size: IVec2, vsync = true): Window =
  ## Creates a new test window with windy-compatible signature.
  Window(
    size: size,
    mousePrevPos: ivec2(0, 0),
    mouseDelta: ivec2(0, 0),
    mousePos: ivec2(0, 0)
  )

proc newSilky*(window: Window, atlas: SilkyAtlas): Silky =
  ## Creates a test Silky context with a fake window.
  discard window
  semantic.newSilky(atlas)

proc newSilky*(window: Window, atlasPngPath: string): Silky =
  ## Creates a test Silky context from one atlas PNG.
  discard window
  semantic.newSilky(atlasPngPath)

proc swapBuffers*(window: Window) {.inline.} =
  ## Stub for swapping buffers.
  discard

proc pollEvents*() {.inline.} =
  ## Stub for polling events.
  discard

proc getClipboardString*(): string =
  ## Stub for getting clipboard content.
  ""

proc makeContextCurrent*(window: Window) {.inline.} =
  ## Stub for OpenGL context creation.
  discard

proc loadExtensions*() {.inline.} =
  ## Stub for loading OpenGL extensions.
  discard

proc resetInputState*(w: Window) =
  ## Resets button pressed and released states for a new frame.
  for i in Button:
    w.buttonPressed[i] = false
    w.buttonReleased[i] = false
  w.mouseDelta = ivec2(0, 0)
  w.scrollDelta = vec2(0, 0)

proc pressButton*(w: Window, button: Button) =
  ## Simulates pressing a mouse button.
  w.buttonDown[button] = true
  w.buttonPressed[button] = true

proc releaseButton*(w: Window, button: Button) =
  ## Simulates releasing a mouse button.
  w.buttonDown[button] = false
  w.buttonReleased[button] = true

proc moveMouse*(w: Window, x, y: int) =
  ## Moves the simulated mouse cursor to the given position.
  let newPos = ivec2(x.int32, y.int32)
  w.mousePrevPos = w.mousePos
  w.mouseDelta = newPos - w.mousePos
  w.mousePos = newPos

proc newTestHarness*(atlas: SilkyAtlas, width = 800, height = 600): TestHarness =
  ## Creates a new test harness from atlas data.
  result.window = newWindow(width, height)
  result.frameCount = 0
  result.sk = Silky()
  result.sk.atlas = atlas
  result.sk.layers[NormalLayer] = @[]
  result.sk.layers[PopupsLayer] = @[]
  result.sk.currentLayer = NormalLayer
  result.sk.layerStack = @[]

proc newTestHarness*(atlasPng: string, width = 800, height = 600): TestHarness =
  ## Creates a new test harness from a single atlas PNG.
  let atlas = readAtlasFromPng(atlasPng)
  newTestHarness(atlas, width, height)

proc beginFrame*(h: var TestHarness) =
  ## Begins a new test frame.
  h.sk.framebufferSize = h.window.size
  h.sk.mousePos = h.window.mousePos.vec2 / h.sk.uiScale
  h.sk.mouseDelta = h.window.mouseDelta.vec2 / h.sk.uiScale
  h.sk.pushLayout(vec2(0, 0), h.window.size.vec2 / h.sk.uiScale)
  h.sk.pushClipRect(rect(0, 0, h.sk.size.x, h.sk.size.y))
  h.sk.semantic.reset()

proc endFrame*(h: var TestHarness) =
  ## Ends the current test frame and captures the snapshot.
  h.sk.popClipRect()
  h.sk.popLayout()
  h.sk.clear()
  inc h.frameCount
  h.lastSnapshot = h.sk.semantic.toSnapshot()

proc pumpFrame*(h: var TestHarness, onFrame: proc(sk: Silky, window: Window), count = 1): string =
  ## Runs one or more frames and returns the diff from the previous snapshot.
  let previousSnapshot = h.lastSnapshot

  for i in 0 ..< count:
    h.beginFrame()
    onFrame(h.sk, h.window)
    h.endFrame()
    h.window.resetInputState()

  result = diff(previousSnapshot, h.lastSnapshot)

proc snapshot*(h: TestHarness): string =
  ## Returns the last captured snapshot.
  h.lastSnapshot

proc findByPath*(h: TestHarness, path: string): SemanticNode =
  ## Finds a node by its dot-separated path.
  h.sk.semantic.root.findByPath(path)

proc findByText*(h: TestHarness, text: string, kind = ""): SemanticNode =
  ## Finds a node by its text content and optional kind.
  h.sk.semantic.root.findByText(text, kind)

proc clickPath*(h: var TestHarness, path: string, onFrame: proc(sk: Silky, window: Window)): string =
  ## Clicks a widget by its path and returns the resulting diff.
  let node = h.findByPath(path)
  if node != nil and node.rect.w > 0:
    let centerX = (node.rect.x + node.rect.w / 2).int
    let centerY = (node.rect.y + node.rect.h / 2).int
    h.window.moveMouse(centerX, centerY)
  h.window.pressButton(MouseLeft)
  discard h.pumpFrame(onFrame)
  h.window.releaseButton(MouseLeft)
  return h.pumpFrame(onFrame)

proc clickLabel*(h: var TestHarness, label: string, onFrame: proc(sk: Silky, window: Window)): string =
  ## Clicks a widget by its text label and returns the resulting diff.
  let node = h.findByText(label)
  if node != nil and node.rect.w > 0:
    let centerX = (node.rect.x + node.rect.w / 2).int
    let centerY = (node.rect.y + node.rect.h / 2).int
    h.window.moveMouse(centerX, centerY)
  h.window.pressButton(MouseLeft)
  discard h.pumpFrame(onFrame)
  h.window.releaseButton(MouseLeft)
  return h.pumpFrame(onFrame)

template mousePos*(w: Window): Vec2 =
  ## Returns the mouse position as a Vec2.
  w.mousePos.vec2

template mouseDelta*(w: Window): Vec2 =
  ## Returns the mouse delta as a Vec2.
  w.mouseDelta.vec2

template buttonDown*(w: Window, btn: Button): bool =
  ## Returns true if the button is currently held down.
  w.buttonDown[btn]

template buttonPressed*(w: Window, btn: Button): bool =
  ## Returns true if the button was just pressed this frame.
  w.buttonPressed[btn]

template buttonReleased*(w: Window, btn: Button): bool =
  ## Returns true if the button was just released this frame.
  w.buttonReleased[btn]

proc pumpFrame*(w: Window, sk: Silky) =
  ## Runs one frame using the window's onFrame callback.
  if w.onFrame != nil:
    w.onFrame()
  w.resetInputState()

proc click*(w: Window, sk: Silky, node: SemanticNode) =
  ## Clicks a semantic node by simulating mouse press and release.
  if node != nil and node.rect.w > 0:
    let centerX = (node.rect.x + node.rect.w / 2).int
    let centerY = (node.rect.y + node.rect.h / 2).int
    w.moveMouse(centerX, centerY)

  w.pressButton(MouseLeft)
  w.pumpFrame(sk)
  w.releaseButton(MouseLeft)
  w.pumpFrame(sk)

proc clickText*(w: Window, sk: Silky, label: string, kind = "") =
  ## Clicks a widget by its text label.
  w.pumpFrame(sk)
  let node = sk.semantic.root.findByText(label, kind)
  w.click(sk, node)

proc clickButton*(w: Window, sk: Silky, label: string) =
  ## Clicks a Button widget by its label.
  w.clickText(sk, label, "Button")

proc getConfig*(appName: string, fileName: string): string =
  ## Stub for reading persistent config in testing mode.
  ""

proc setConfig*(appName: string, fileName: string, content: string) =
  ## Stub for writing persistent config in testing mode.
  discard

proc openUrl*(url: string) =
  ## Stub for opening a URL in testing mode.
  discard

proc openTempTextFile*(title, text: string) =
  ## Stub for opening a temp text file in testing mode.
  discard
