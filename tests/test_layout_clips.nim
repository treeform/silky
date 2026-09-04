import
  bumpy, chroma, vmath,
  silky

proc testClips(
  direction: StackDirection,
  nested, constrained, popup: bool
) =
  ## Checks native vertex placement, clipping, and layer preservation.
  let
    builder = newAtlasBuilder(64, 2)
    sk = Silky(atlas: builder.atlas, image: builder.atlasImage)
    window = Window(nil)
    viewport = rect(0, 0, 400, 300)
    ancestor =
      if constrained:
        rect(60, 55, 20, 10)
      else:
        viewport
  new(sk.drawer)
  sk.pushLayout(vec2(0, 0), viewport.wh)
  sk.pushClipRect(viewport)
  sk.pushClipRect(ancestor)
  sk.pushLayer(PopupsLayer)
  sk.drawRect(vec2(2, 3), vec2(4, 5), rgbx(255, 255, 255, 255))
  sk.popLayer()

  template children() =
    ## Draws clipped content and an optional popup escaping that clip.
    rectangle "clipped":
      size 40, 20
      clipContent()
      itemSpacing 0
      rectangle "paint":
        size 40, 20
        tint "#ff0000"
      if popup:
        sk.pushLayer(PopupsLayer)
        sk.pushRawClipRect(viewport)
        sk.drawRect(sk.pos, vec2(40, 20), rgbx(255, 0, 0, 255))
        sk.popClipRect()
        sk.popLayer()

  ui:
    group "outer":
      box 50, 50, 200, 200
      rectangle "hugger":
        hug()
        layout direction
        itemSpacing 0
        tint "#0000ff"
        if nested:
          rectangle "nested":
            hug()
            layout BottomToTop
            itemSpacing 0
            tint "#00ff00"
            children()
        else:
          children()

  doAssert sk.clipRect == ancestor
  doAssert sk.drawer.layers[PopupsLayer][0].pos == vec2(2, 3)
  for layer in 0 .. 1:
    var
      count = 0
      minimum = vec2(10000, 10000)
      maximum = vec2(-10000, -10000)
    let expectedClip =
      if layer == PopupsLayer:
        viewport
      elif constrained:
        ancestor
      else:
        rect(50, 50, 40, 20)
    for vertex in sk.drawer.layers[layer]:
      if vertex.color == rgbx(255, 0, 0, 255):
        inc count
        minimum = min(minimum, vertex.pos)
        maximum = max(maximum, vertex.pos)
        doAssert vertex.clipPos == expectedClip.xy
        doAssert vertex.clipSize == expectedClip.wh
    if layer == NormalLayer or popup:
      doAssert count == 6
      doAssert minimum == vec2(50, 50)
      doAssert maximum == vec2(90, 70)
    else:
      doAssert count == 0
  sk.popClipRect()
  sk.popClipRect()
  sk.popLayout()
  sk.clear()

echo "Testing hug clipping with native vertices in four directions"
for direction in StackDirection:
  for nested in [false, true]:
    for constrained in [false, true]:
      for popup in [false, true]:
        testClips(direction, nested, constrained, popup)
echo "All 32 native layout clipping cases passed."
