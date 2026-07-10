## Test harness for Silky UI testing without a real window or GPU.

import
  std/unicode,
  vmath, bumpy,
  silky/[semantics, atlas]
from windy/common import Button, CursorKind, Cursor
export Button, CursorKind, Cursor, unicode

type Window* = ref object
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
