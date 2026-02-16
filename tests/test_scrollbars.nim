import vmath, bumpy, silky/scrollbars

echo "Testing contentSize"
block:
  var sa = ScrollArea(contentMin: vec2(10, 20), contentMax: vec2(110, 220))
  doAssert sa.contentSize == vec2(100, 200), "contentSize should be max - min"

echo "Testing contentSize with reversed min/max clamps to zero"
block:
  var sa = ScrollArea(contentMin: vec2(100, 100), contentMax: vec2(50, 50))
  doAssert sa.contentSize == vec2(0, 0), "contentSize should clamp negative to zero"

echo "Testing scrollMax when content fits"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(100, 100),
    viewPos: vec2(0, 0), viewSize: vec2(200, 200)
  )
  doAssert sa.scrollMax == vec2(0, 0), "scrollMax should be zero when content fits"

echo "Testing scrollMax when content overflows"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(500, 300),
    viewPos: vec2(0, 0), viewSize: vec2(200, 200)
  )
  doAssert sa.scrollMax == vec2(300, 100), "scrollMax should be content - view"

echo "Testing needsScrollX and needsScrollY"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(500, 100),
    viewPos: vec2(0, 0), viewSize: vec2(200, 200)
  )
  doAssert sa.needsScrollX == true, "needs X scroll"
  doAssert sa.needsScrollY == false, "does not need Y scroll"

echo "Testing clampScroll"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(500, 500),
    viewPos: vec2(0, 0), viewSize: vec2(200, 200),
    scrollPos: vec2(999, -10)
  )
  sa.clampScroll()
  doAssert sa.scrollPos.x == 300, "x clamped to scrollMax"
  doAssert sa.scrollPos.y == 0, "y clamped to 0"

echo "Testing clampScroll when no overflow"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(100, 100),
    viewPos: vec2(0, 0), viewSize: vec2(200, 200),
    scrollPos: vec2(50, 50)
  )
  sa.clampScroll()
  doAssert sa.scrollPos == vec2(0, 0), "scroll reset to zero when no overflow"

echo "Testing scrollOffset"
block:
  var sa = ScrollArea(scrollPos: vec2(30, 50))
  doAssert sa.scrollOffset == vec2(-30, -50), "offset is negative scrollPos"

echo "Testing initScroll with top-left anchor (no auto-scroll)"
block:
  var sa = ScrollArea(
    contentMin: vec2(10, 10), contentMax: vec2(500, 500),
    viewPos: vec2(10, 10), viewSize: vec2(200, 200)
  )
  sa.initScroll()
  doAssert sa.scrollPos == vec2(0, 0), "no auto-scroll for normal anchor"
  doAssert sa.initialized == true, "marked initialized"

echo "Testing initScroll with bottom anchor (content above viewport)"
block:
  var sa = ScrollArea(
    contentMin: vec2(10, -200), contentMax: vec2(300, 210),
    viewPos: vec2(10, 10), viewSize: vec2(200, 200)
  )
  sa.initScroll()
  doAssert sa.scrollPos.y == sa.scrollMax.y, "y scrolled to max for bottom anchor"
  doAssert sa.scrollPos.x == 0, "x stays zero"

echo "Testing initScroll with right anchor (content left of viewport)"
block:
  var sa = ScrollArea(
    contentMin: vec2(-200, 10), contentMax: vec2(210, 300),
    viewPos: vec2(10, 10), viewSize: vec2(200, 200)
  )
  sa.initScroll()
  doAssert sa.scrollPos.x == sa.scrollMax.x, "x scrolled to max for right anchor"
  doAssert sa.scrollPos.y == 0, "y stays zero"

echo "Testing initScroll with bottom-right anchor"
block:
  var sa = ScrollArea(
    contentMin: vec2(-200, -200), contentMax: vec2(210, 210),
    viewPos: vec2(10, 10), viewSize: vec2(200, 200)
  )
  sa.initScroll()
  doAssert sa.scrollPos.x == sa.scrollMax.x, "x scrolled to max"
  doAssert sa.scrollPos.y == sa.scrollMax.y, "y scrolled to max"

echo "Testing initScroll only runs once"
block:
  var sa = ScrollArea(
    contentMin: vec2(10, -200), contentMax: vec2(300, 210),
    viewPos: vec2(10, 10), viewSize: vec2(200, 200)
  )
  sa.initScroll()
  let firstY = sa.scrollPos.y
  sa.scrollPos.y = 0
  sa.initScroll()
  doAssert sa.scrollPos.y == 0, "initScroll should not run twice"

echo "Testing initScroll skips when no overflow"
block:
  var sa = ScrollArea(
    contentMin: vec2(10, 10), contentMax: vec2(100, 100),
    viewPos: vec2(10, 10), viewSize: vec2(200, 200)
  )
  sa.initScroll()
  doAssert sa.initialized == false, "not initialized when no overflow"

echo "Testing applyWheel"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(500, 500),
    viewPos: vec2(0, 0), viewSize: vec2(200, 200),
    scrollPos: vec2(100, 100)
  )
  sa.applyWheel(vec2(0, -10), -10.0)
  doAssert sa.scrollPos.y == 200, "wheel scrolled down"
  doAssert sa.scrollPos.x == 100, "x unchanged"

echo "Testing scrollBarY rects"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(200, 400),
    viewPos: vec2(10, 20), viewSize: vec2(200, 200),
    scrollPos: vec2(0, 0)
  )
  let (track, handle) = sa.scrollBarY
  doAssert track.x == 200, "track x at right edge - 10"
  doAssert track.y == 22, "track y at viewPos.y + 2"
  doAssert track.w == 8, "track width is 8"
  doAssert handle.y == track.y, "handle at top when scrollPos is 0"

echo "Testing scrollBarX rects"
block:
  var sa = ScrollArea(
    contentMin: vec2(0, 0), contentMax: vec2(400, 200),
    viewPos: vec2(10, 20), viewSize: vec2(200, 200),
    scrollPos: vec2(0, 0)
  )
  let (track, handle) = sa.scrollBarX
  doAssert track.y == 210, "track y at bottom edge - 10"
  doAssert track.x == 12, "track x at viewPos.x + 2"
  doAssert track.h == 8, "track height is 8"
  doAssert handle.x == track.x, "handle at left when scrollPos is 0"

echo "Testing releaseIfUp"
block:
  var sa = ScrollArea(scrollingX: true, scrollingY: true)
  sa.releaseIfUp(true)
  doAssert sa.scrollingX == true, "still dragging when mouse down"
  sa.releaseIfUp(false)
  doAssert sa.scrollingX == false, "released on mouse up"
  doAssert sa.scrollingY == false, "released on mouse up"

echo "All scroll tests passed."
