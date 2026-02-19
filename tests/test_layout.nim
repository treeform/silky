import
  std/unittest,
  silky/[layout, common],
  vmath

type
  LayoutCase = object
    direction: StackDirection
    anchor: Anchor
    expectedStart: Vec2
    expectedPos: Vec2

const Cases = [
  LayoutCase(direction: TopToBottom, anchor: AnchorLeft, expectedStart: vec2(10, 20), expectedPos: vec2(10, 20)),
  LayoutCase(direction: TopToBottom, anchor: AnchorRight, expectedStart: vec2(110, 20), expectedPos: vec2(85, 20)),
  LayoutCase(direction: BottomToTop, anchor: AnchorLeft, expectedStart: vec2(10, 70), expectedPos: vec2(10, 55)),
  LayoutCase(direction: BottomToTop, anchor: AnchorRight, expectedStart: vec2(110, 70), expectedPos: vec2(85, 55)),
  LayoutCase(direction: LeftToRight, anchor: AnchorTop, expectedStart: vec2(10, 20), expectedPos: vec2(10, 20)),
  LayoutCase(direction: LeftToRight, anchor: AnchorBottom, expectedStart: vec2(10, 70), expectedPos: vec2(10, 55)),
  LayoutCase(direction: RightToLeft, anchor: AnchorTop, expectedStart: vec2(110, 20), expectedPos: vec2(85, 20)),
  LayoutCase(direction: RightToLeft, anchor: AnchorBottom, expectedStart: vec2(110, 70), expectedPos: vec2(85, 55)),
]

suite "Layout module":
  test "Layout stack push and pop keeps full state":
    var stack: seq[Layout]
    var parent = initLayout(vec2(10, 20), vec2(100, 50), TopToBottom, AnchorRight)
    parent.at = vec2(33, 44)
    parent.num = 7
    parent.stretchMin = vec2(2, 3)
    parent.stretchMax = vec2(80, 90)
    pushLayout(stack, parent)
    var child = initLayout(vec2(0, 0), vec2(20, 10), LeftToRight, AnchorBottom)
    advanceLayout(child, vec2(8, 6), 2'f32)
    check child.num == 1
    let restored = popLayout(stack)
    check restored.at == vec2(33, 44)
    check restored.num == 7
    check restored.pos == vec2(10, 20)
    check restored.size == vec2(100, 50)
    check restored.direction == TopToBottom
    check restored.anchor == AnchorRight
    check restored.stretchMin == vec2(2, 3)
    check restored.stretchMax == vec2(80, 90)

  test "Basis, start, and widget position":
    let
      containerPos = vec2(10, 20)
      containerSize = vec2(100, 50)
      childSize = vec2(25, 15)
    for c in Cases:
      let
        layout = initLayout(containerPos, containerSize, c.direction, c.anchor)
        startPos = layoutStart(containerPos, containerSize, c.direction, c.anchor)
        widgetPos = layoutWidgetPos(startPos, childSize, c.direction, c.anchor)
      check startPos == c.expectedStart
      check widgetPos == c.expectedPos
      check (layout.mainDir.x == 0) xor (layout.mainDir.y == 0)
      check abs(layout.mainDir.x) + abs(layout.mainDir.y) == 1

  test "Padding offset and advance delta":
    let
      padding = vec2(8, 6)
      amount = vec2(25, 15)
      spacing = 4'f32
    check layoutPaddingOffset(padding, TopToBottom, AnchorLeft) == vec2(8, 6)
    check layoutPaddingOffset(padding, TopToBottom, AnchorRight) == vec2(-8, 6)
    check layoutPaddingOffset(padding, BottomToTop, AnchorLeft) == vec2(8, -6)
    check layoutPaddingOffset(padding, BottomToTop, AnchorRight) == vec2(-8, -6)
    check layoutPaddingOffset(padding, LeftToRight, AnchorTop) == vec2(8, 6)
    check layoutPaddingOffset(padding, LeftToRight, AnchorBottom) == vec2(8, -6)
    check layoutPaddingOffset(padding, RightToLeft, AnchorTop) == vec2(-8, 6)
    check layoutPaddingOffset(padding, RightToLeft, AnchorBottom) == vec2(-8, -6)
    check layoutAdvanceDelta(amount, TopToBottom, spacing) == vec2(0, 19)
    check layoutAdvanceDelta(amount, BottomToTop, spacing) == vec2(0, -19)
    check layoutAdvanceDelta(amount, LeftToRight, spacing) == vec2(29, 0)
    check layoutAdvanceDelta(amount, RightToLeft, spacing) == vec2(-29, 0)

  test "Rectangle helpers":
    var
      minPos = vec2(1000, 1000)
      maxPos = vec2(-1000, -1000)
    includeRect(minPos, maxPos, vec2(10, 20), vec2(30, 15))
    includeRect(minPos, maxPos, vec2(5, 18), vec2(10, 40))
    check minPos == vec2(5, 18)
    check maxPos == vec2(40, 58)
    let r = rectFromMinMax(minPos, maxPos)
    check r.x == 5 and r.y == 18
    check r.w == 35 and r.h == 40

  test "Advance updates stretch in layout object":
    var lay = initLayout(vec2(10, 20), vec2(100, 50), RightToLeft, AnchorTop)
    check lay.stretchMin == lay.at
    check lay.stretchMax == lay.at
    advanceLayout(lay, vec2(25, 15), 4'f32)
    check lay.stretchMin == vec2(110, 20)
    check lay.stretchMax == vec2(139, 39)
    check lay.at == vec2(81, 20)
    check lay.num == 1
