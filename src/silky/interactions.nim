import
  vmath, bumpy

type
  HitRegion = object
    bounds, clip: Rect
    layer: int

  Interactor* = object
    ## Resolves pointer targets against the last displayed frame.
    currentId*: int = -1
    warmId*: int = -1
    warmLayer*: int = -1
    hotId*: int = -1
    previous, current: seq[HitRegion]
    resolvedMouse: Vec2
    invalidated: bool

proc resetInteractions*(interactor: var Interactor) =
  ## Invalidates the previous targets without discarding this frame's regions.
  interactor.hotId = -1
  interactor.warmId = -1
  interactor.warmLayer = -1
  interactor.previous.setLen(0)
  if interactor.currentId >= 0:
    interactor.invalidated = true

proc endInteractions*(interactor: var Interactor) =
  ## Retains displayed hit regions and reuses the other frame's storage.
  interactor.hotId = interactor.warmId
  interactor.warmId = -1
  interactor.warmLayer = -1
  interactor.currentId = -1
  if interactor.invalidated:
    interactor.previous.setLen(0)
    interactor.invalidated = false
  else:
    swap(interactor.previous, interactor.current)
  interactor.current.setLen(0)

proc mouseHover*(
  interactor: var Interactor,
  mousePos: Vec2,
  clipRect: Rect,
  layer: int,
  widgetRect: Rect
): bool =
  ## Resolves pointer changes without renumbering this frame's hit regions.
  if interactor.currentId == -1 or mousePos != interactor.resolvedMouse:
    # Applications may mask background input before drawing a popup.
    interactor.resolvedMouse = mousePos
    interactor.hotId = -1
    var hotLayer = -1
    for id, region in interactor.previous:
      if region.layer >= hotLayer and mousePos.overlaps(region.bounds) and
        mousePos.overlaps(region.clip):
          interactor.hotId = id
          hotLayer = region.layer
  inc interactor.currentId
  let
    region = HitRegion(bounds: widgetRect, clip: clipRect, layer: layer)
    hovering = mousePos.overlaps(widgetRect) and mousePos.overlaps(clipRect)
  interactor.current.add(region)
  if hovering and layer >= interactor.warmLayer:
    interactor.warmLayer = layer
    interactor.warmId = interactor.currentId
  # A moved, replaced, or newly clipped target must not inherit a stale hit.
  interactor.hotId == interactor.currentId and hovering and
    interactor.currentId < interactor.previous.len and
    interactor.previous[interactor.currentId] == region
