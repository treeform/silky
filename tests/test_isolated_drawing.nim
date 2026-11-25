import
  bumpy, chroma, vmath,
  silky

when defined(silkyTesting):
  from silky/semantics import textInputs
else:
  from silky/contexts import textInputs

const
  Viewport = rect(0, 0, 400, 300)
  Red = rgbx(255, 0, 0, 255)
  Green = rgbx(0, 255, 0, 255)
  Blue = rgbx(0, 0, 255, 255)

template layers(sk: Silky): untyped =
  ## Reads native queues or the test window's matching queue representation.
  when defined(silkyTesting):
    sk.layers
  else:
    sk.drawer.layers

proc fixture(): Silky =
  ## Creates drawing state without a graphics context on either test path.
  let builder = newAtlasBuilder(64, 2)
  when defined(silkyTesting):
    let window = newWindow(400, 300)
    result = newSilky(window, builder.atlas)
    result.beginUi(window, window.size)
  else:
    result = Silky(atlas: builder.atlas, image: builder.atlasImage)
    new(result.drawer)
    result.pushLayout(Viewport.xy, Viewport.wh)
    result.pushClipRect(Viewport)

proc paint(sk: Silky, position, size: Vec2, color: ColorRGBX) =
  ## Exercises real native vertices and queues equivalent semantic markers.
  sk.drawRect(position, size, color)
  when defined(silkyTesting):
    sk.layers[sk.currentDrawLayer].add(SilkyVertex(
      pos: position,
      size: size,
      color: color,
      clipPos: sk.clipRect.xy,
      clipSize: sk.clipRect.wh
    ))

proc bake(sk: Silky, fail = false) =
  ## Draws a nested offscreen pass while an outer deferred span is active.
  let
    queued = sk.layers
    layouts = sk.layoutStack
    layer = sk.currentDrawLayer
    clip = sk.clipRect
    inputs = sk.textInputs()
  var raised = false
  try:
    sk.isolatedDrawing(rect(0, 0, 80, 60)):
      doAssert sk.layers[0].len == 0 and sk.layers[1].len == 0
      doAssert sk.currentDrawLayer == NormalLayer
      doAssert sk.rootSize == vec2(80, 60)
      doAssert sk.clipRect == rect(0, 0, 80, 60)
      doAssert sk.textInputs().isNil
      sk.beginWidget("Offscreen", "isolated")
      sk.pushClipRect(rect(4, 5, 40, 30))
      let span = sk.beginVertexSpan()
      sk.paint(vec2(7, 8), vec2(10, 12), Green)
      sk.pushLayer(PopupsLayer)
      sk.paint(vec2(10, 11), vec2(12, 13), Blue)
      let
        nestedQueued = sk.layers
        nestedLayouts = sk.layoutStack
        nestedClip = sk.clipRect
      sk.isolatedDrawing(rect(2, 3, 16, 12)):
        doAssert sk.currentDrawLayer == NormalLayer
        doAssert sk.clipRect == rect(2, 3, 16, 12)
        sk.paint(vec2(2, 3), vec2(4, 5), Red)
        sk.pushLayer(PopupsLayer)
        sk.pushClipRect(rect(3, 4, 5, 6))
        discard sk.beginVertexSpan()
        # Unfinished local drawing stacks must not escape the scope.
      doAssert sk.layers == nestedQueued
      doAssert sk.layoutStack == nestedLayouts
      doAssert sk.clipRect == nestedClip
      doAssert sk.currentDrawLayer == PopupsLayer
      sk.popLayer()
      sk.endVertexSpan(span, vec2(1, 2))
      sk.popClipRect()
      sk.endWidget()
      if fail:
        sk.pushLayer(PopupsLayer)
        sk.pushClipRect(rect(1, 1, 2, 2))
        discard sk.beginVertexSpan()
        raise newException(ValueError, "Offscreen drawing failed")
  except ValueError:
    raised = true
  doAssert raised == fail
  doAssert sk.layers == queued
  doAssert sk.layoutStack == layouts
  doAssert sk.currentDrawLayer == layer
  doAssert sk.clipRect == clip
  doAssert sk.textInputs() == inputs

proc testScopes(fail: bool) =
  ## Preserves both layer queues and active capture metadata through nesting.
  let sk = fixture()
  sk.paint(vec2(1, 2), vec2(3, 4), Blue)
  let span = sk.beginVertexSpan()
  sk.pushClipRect(rect(10, 20, 100, 80))
  sk.paint(vec2(12, 23), vec2(10, 11), Red)
  sk.pushLayer(PopupsLayer)
  sk.paint(vec2(14, 25), vec2(12, 13), Green)
  sk.bake(fail)
  sk.paint(vec2(16, 27), vec2(14, 15), Red)
  sk.popLayer()
  sk.paint(vec2(18, 29), vec2(16, 17), Green)
  sk.popClipRect()
  sk.endVertexSpan(span, vec2(30, 40))
  doAssert sk.currentDrawLayer == NormalLayer
  doAssert sk.clipRect == Viewport
  when not defined(silkyTesting):
    doAssert sk.drawer.layers[NormalLayer].len == 18
    doAssert sk.drawer.layers[PopupsLayer].len == 12
    doAssert sk.drawer.layers[NormalLayer][0].pos == vec2(1, 2)
    for layer in 0 .. 1:
      let first = if layer == NormalLayer: 6 else: 0
      for vertex in sk.drawer.layers[layer][first .. ^1]:
        doAssert vertex.clipPos == vec2(40, 60)
        doAssert vertex.clipSize == vec2(100, 80)

proc drawHud(isolate: bool, direction: StackDirection): Silky =
  ## Inserts offscreen drawing between children of nested deferred layouts.
  result = fixture()
  let
    sk = result
    window = Window(nil)
  sk.pushLayer(PopupsLayer)
  sk.paint(vec2(2, 3), vec2(4, 5), Blue)
  sk.popLayer()
  ui:
    group "outer":
      box 50, 50, 200, 200
      rectangle "hugger":
        hug()
        layout direction
        itemSpacing 0
        tint "#0000ff"
        rectangle "nested":
          hug()
          layout BottomToTop
          itemSpacing 0
          rectangle "before":
            size 40, 20
            clipContent()
            tint "#ff0000"
          if isolate:
            sk.pushLayer(PopupsLayer)
            sk.bake()
            sk.bake(fail = true)
            sk.popLayer()
          rectangle "after":
            size 30, 10
            clipContent()
            tint "#00ff00"

echo "Testing isolated drawing queues, nested scopes, and exception cleanup"
for fail in [false, true]:
  testScopes(fail)
for direction in StackDirection:
  let
    reference = drawHud(false, direction)
    actual = drawHud(true, direction)
  doAssert actual.layers == reference.layers
  doAssert actual.layoutStack == reference.layoutStack
  doAssert actual.currentDrawLayer == reference.currentDrawLayer
  doAssert actual.clipRect == reference.clipRect
  when defined(silkyTesting):
    doAssert actual.semantic.toSnapshot() == reference.semantic.toSnapshot()
echo "Isolated drawing preserves deferred HUD placement and clips."
