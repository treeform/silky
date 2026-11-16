import
  std/[importutils, tables],
  bumpy, pixie, vmath, windy,
  silky, silky/internal/inputs

proc fixture(builder: AtlasBuilder): Silky =
  ## Queues native rich widget drawing without opening a platform window.
  privateAccess(Silky)
  result = Silky(
    atlas: builder.atlas,
    image: builder.atlasImage,
    uiScale: 2,
    inFrame: true,
    inputs: TextInputs()
  )
  new(result.drawer)
  result.theme.padding = 0
  result.mousePos = vec2(-1)
  result.pushLayout(vec2(0), vec2(600))
  result.pushClipRect(rect(0, 0, 600, 600))

proc patches(sk: Silky, name: string): seq[Rect] =
  ## Collects native scrollbar quads using their packed atlas region.
  let
    sprite = sk.atlas.entries[name]
    vertices = sk.drawer.layers[NormalLayer]
  for i in countup(0, vertices.high, 6):
    let uv = vertices[i].uv
    if uv.x >= sprite.x.float32 and
      uv.x < (sprite.x + sprite.width).float32 and
      uv.y >= sprite.y.float32 and
      uv.y < (sprite.y + sprite.height).float32:
        result.add(rect(
          vertices[i].pos,
          vertices[i + 2].pos - vertices[i].pos
        ))

block:
  echo "Testing mixed rich text reserves native horizontal scrollbar space"
  const Source = "WW WW WW WW WW WW WW WW WW WW"
  let builder = newAtlasBuilder(1024, 2)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 18)
  for name in [
    "textbox.disabled.9patch",
    "scrollbar.track.9patch",
    "scrollbar.9patch"
  ]:
    doAssert builder.addImage(name, newImage(16, 16))
  let
    sk = fixture(builder)
    state = newRichTextBoxState(Source)
  state.blocks = @[
    TextBlock(first: 0, last: Source.len, noWrap: true)
  ]
  state.computeLayout(builder.atlas.fonts, "Default", 100)
  richTextBoxStates["scroll-test"] = state
  let height = state.innerHeight + state.horizontalScrollbarHeight(100)
  sk.richTextBox(
    Window(), "scroll-test", Source, 100, height, blocks = state.blocks
  )
  doAssert abs(state.editor.boxSize.y - state.innerHeight) < 0.001
  doAssert state.editor.scrollPos.y == 0
  doAssert state.editor.wordWrap
  let bars = sk.patches("scrollbar.9patch")
  doAssert bars.len > 0
  for bounds in bars:
    doAssert bounds.y >= state.innerHeight

  echo "Testing horizontal offsets reset when a table fits after resizing"
  state.editor.scrollPos.x = 200
  state.computeLayout(builder.atlas.fonts, "Default", 600)
  sk.drawer.layers[NormalLayer].setLen(0)
  sk.at = vec2(0)
  sk.richTextBox(
    Window(), "scroll-test", Source, 600, state.innerHeight,
    blocks = state.blocks
  )
  doAssert state.horizontalScrollbarHeight(600) == 0
  doAssert state.editor.scrollPos.x == 0
  doAssert sk.patches("scrollbar.9patch").len == 0
  richTextBoxStates.del("scroll-test")

echo "All rich scrollbar tests passed."
