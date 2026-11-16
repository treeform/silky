import vmath

const
  TextPressDelay* = 500.0
  TextPressSlop = 6.0'f

type
  TextPressResult* = enum
    NoTextPress, WaitingTextPress, HeldTextPress, ReleasedTextPress

  TextPress* = object
    active*: bool
    preserve*: bool
    position*: Vec2
    started*: float64

proc beginTextPress*(position: Vec2, nowMs: float64, preserve: bool): TextPress =
  ## Records a stationary touch without discarding an existing selection.
  TextPress(active: true, position: position, started: nowMs, preserve: preserve)

proc updateTextPress*(
  press: var TextPress, point: Vec2, down, released, cancelled: bool,
  nowMs: float64
): TextPressResult =
  ## Recognizes a hold while rejecting pans and interrupted gestures.
  if not press.active:
    return NoTextPress
  let distance = point - press.position
  if cancelled or max(abs(distance.x), abs(distance.y)) >= TextPressSlop:
    press.active = false
    return NoTextPress
  if released:
    press.active = false
    return ReleasedTextPress
  if not down:
    press.active = false
    return NoTextPress
  if nowMs - press.started >= TextPressDelay:
    press.active = false
    return HeldTextPress
  WaitingTextPress
