import
  std/monotimes,
  vmath

from windy/common import Button

type
  RenderMode* = enum
    ContinuousRender, OnDemandRender

  FrameSchedule* = object
    mode*: RenderMode
    wake*: proc()
    dirty: bool = true
    deadline: int64 = int64.high

  FrameInput* = object
    initialized: bool
    position, size: IVec2
    focused, visible, minimized: bool
    scale: float32

proc frameMilliseconds*(): int64 {.raises: [].} =
  ## Reads the monotonic clock used for redraw deadlines.
  getMonoTime().ticks div 1_000_000

proc requestFrame*(
  schedule: var FrameSchedule,
  delayMs = 0,
  nowMs = frameMilliseconds()
) =
  ## Requests an immediate or timed redraw from the owning UI thread.
  ## Timed requests keep the earliest deadline; visible animations renew them.
  let
    dirty = schedule.dirty
    deadline = schedule.deadline
  if delayMs <= 0:
    schedule.dirty = true
  else:
    schedule.deadline = min(schedule.deadline, nowMs + delayMs.int64)
  if (schedule.dirty != dirty or schedule.deadline < deadline) and
    schedule.wake != nil:
      schedule.wake()

proc needsFrame*(schedule: FrameSchedule, nowMs = frameMilliseconds()): bool
    {.raises: [].} =
  ## Reports continuous rendering, invalidation, or an expired deadline.
  schedule.mode == ContinuousRender or schedule.dirty or
    schedule.deadline <= nowMs

proc nextFrameDelay*(
  schedule: FrameSchedule,
  maxWaitMs = 1000,
  nowMs = frameMilliseconds()
): int {.raises: [].} =
  ## Returns the bounded native-event wait until another frame is due.
  if schedule.needsFrame(nowMs):
    return 0
  let limit = max(0, maxWaitMs)
  if schedule.deadline == int64.high:
    return limit
  min(limit.int64, max(0'i64, schedule.deadline - nowMs)).int

proc beginFrame*(schedule: var FrameSchedule, nowMs = frameMilliseconds())
    {.raises: [].} =
  ## Consumes invalidation and expired timers before drawing the next frame.
  schedule.dirty = false
  if schedule.deadline <= nowMs:
    schedule.deadline = int64.high

proc inputChanged*(
  previous: var FrameInput,
  window: auto,
  pendingText: bool
): bool =
  ## Detects native geometry, pointer, focus, and queued editor input changes.
  let
    position = window.mousePos
    size = window.size
    focused =
      when compiles(window.focused): window.focused
      else: true
    visible =
      when compiles(window.visible): window.visible
      else: true
    minimized =
      when compiles(window.minimized): window.minimized
      else: false
    scale =
      when compiles(window.contentScale): window.contentScale
      else: 1.0'f
  result = pendingText or not previous.initialized or
    position != previous.position or size != previous.size or
    focused != previous.focused or visible != previous.visible or
    minimized != previous.minimized or scale != previous.scale or
    window.scrollDelta != vec2(0) or window.mouseDelta != ivec2(0)
  for button in Button:
    if window.buttonPressed[button] or window.buttonReleased[button]:
      result = true
      break
  previous = FrameInput(
    initialized: true,
    position: position,
    size: size,
    focused: focused,
    visible: visible,
    minimized: minimized,
    scale: scale
  )
