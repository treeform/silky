import
  std/[importutils, tables],
  bumpy, pixie, vmath, windy,
  silky, silky/internal/inputs

privateAccess(Silky)

proc fixture(builder: AtlasBuilder): Silky =
  ## Queues native image and text vertices without opening a platform window.
  result = Silky(
    atlas: builder.atlas,
    image: builder.atlasImage,
    uiScale: 2,
    inFrame: true,
    inputs: TextInputs(),
    window: Window()
  )
  new(result.drawer)
  result.theme.padding = 0
  result.mousePos = vec2(-1)
  result.pushLayout(vec2(0), vec2(600))
  result.pushClipRect(rect(0, 0, 600, 600))

block:
  echo "Testing native rich images preserve aspect, cropping and selection"
  let builder = newAtlasBuilder(1024, 2)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
  for name in [
    "textbox.disabled.9patch", "scrollbar.track.9patch", "scrollbar.9patch"
  ]:
    doAssert builder.addImage(name, newImage(16, 16))
  doAssert builder.addImage("picture", newImage(512, 512))
  let
    sk = fixture(builder)
    state = newRichTextBoxState("An image\n\nAfter the image.")
  state.blocks = @[
    TextBlock(
      first: 0,
      last: 8,
      image: "picture",
      imageSize: vec2(320, 180),
      imagePixels: vec2(320, 180),
      padding: vec2(12, 6),
      spacing: 8
    ),
    TextBlock(first: 10, last: 26, padding: vec2(12, 6))
  ]
  state.computeLayout(builder.atlas.fonts, "Default", 184)
  let bounds = state.imageBounds(0)
  doAssert bounds == rect(12, 6, 160, 90)
  doAssert state.editor.layout[0].y == bounds.y + bounds.h + 8
  doAssert state.editor.layout[10].y > state.editor.layout[0].y
  doAssert state.imageBounds(1).w == 0
  state.editor.selectAll()
  doAssert state.editor.copyText() == "An image\n\nAfter the image."
  richTextBoxStates["images"] = state
  sk.richTextBox(
    sk.window, "images", state.getText(), 184, state.innerHeight,
    blocks = state.blocks
  )
  let
    sprite = sk.atlas.entries["picture"]
    vertices = sk.drawer.layers[NormalLayer]
  var found = false
  for i in countup(0, vertices.high, 6):
    if vertices[i].uv == vec2(sprite.x.float32, sprite.y.float32):
      doAssert not found
      found = true
      doAssert vertices[i].pos == bounds.xy
      doAssert vertices[i + 2].pos - vertices[i].pos == bounds.wh
      doAssert vertices[i + 2].uv - vertices[i].uv == vec2(320, 180)
  doAssert found
  doAssert state.editor.scrollPos == vec2(0)
  richTextBoxStates.del("images")

echo "All native rich image tests passed."
