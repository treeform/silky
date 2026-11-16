import
  std/[importutils, tables],
  bumpy, pixie, vmath, windy,
  silky, silky/internal/inputs

const FontPath = "tests/data/IBMPlexSans-Regular.ttf"

proc close(a, b: float32): bool =
  ## Compares font and button positions with float tolerance.
  abs(a - b) < 0.001

proc fixture(builder: AtlasBuilder, density: float32): Silky =
  ## Queues native button vertices without a platform window or GPU.
  privateAccess(Silky)
  result = Silky(
    atlas: builder.atlas,
    image: builder.atlasImage,
    uiScale: density,
    inFrame: true,
    inputs: TextInputs(),
    window: Window()
  )
  new(result.drawer)
  result.mousePos = vec2(-1)
  result.pushLayout(vec2(0), vec2(400))
  result.pushClipRect(rect(0, 0, 400, 400))

proc glyphPosition(sk: Silky): Vec2 =
  ## Finds the W glyph quad by its atlas entry.
  let
    glyph = sk.atlas.fonts["Default"].entries["W"][0]
    uv = vec2(glyph.x.float32, glyph.y.float32)
  for vertex in sk.drawer.layers[NormalLayer]:
    if vertex.uv == uv:
      return vertex.pos
  doAssert false, "The button label must use the native glyph atlas."

block:
  echo "Testing minimum-size button text stays left and vertically centered"
  for density in [1.0'f, 1.25'f, 1.5'f, 2.0'f]:
    let builder = newAtlasBuilder(256, 2)
    builder.addFont(
      FontPath, "Default", 18, @["W"], pixelScale = density
    )
    doAssert builder.addImage("button.9patch", newImage(24, 24))
    let
      sk = fixture(builder, density)
      reference = fixture(builder, density)
      origin = vec2(20.17'f, 30.29'f)
      textSize = sk.getTextSize("Default", "W")
      padding = sk.theme.padding.float32
      spacing = sk.theme.spacing.float32
      expected = origin + vec2(padding, (64 - textSize.y) / 2)
    sk.at = origin
    button("W", vec2(180, 64)):
      doAssert false, "A button outside the pointer must not activate."
    discard reference.drawText(
      "Default", "W", expected, sk.theme.defaultTextColor
    )
    let
      actualGlyph = sk.glyphPosition()
      expectedGlyph = reference.glyphPosition()
    doAssert close(actualGlyph.x, expectedGlyph.x)
    doAssert close(actualGlyph.y, expectedGlyph.y)
    doAssert actualGlyph.x < origin.x + 30,
      "The label must not center horizontally across the wide button."
    doAssert actualGlyph.y > origin.y + padding,
      "The taller button must center the label vertically."
    doAssert close(sk.at.y, origin.y + 64 + padding + spacing),
      "Native layout must advance by the actual button height."

    sk.drawer.layers[NormalLayer].setLen(0)
    reference.drawer.layers[NormalLayer].setLen(0)
    sk.at = origin
    button("W"):
      discard
    discard reference.drawText(
      "Default", "W", origin + vec2(padding), sk.theme.defaultTextColor
    )
    let legacy = sk.glyphPosition()
    doAssert close(legacy.x, reference.glyphPosition().x)
    doAssert close(legacy.y, reference.glyphPosition().y)
    doAssert close(sk.at.y, origin.y + textSize.y + padding * 3 + spacing)

echo "All native button vertex tests passed."
