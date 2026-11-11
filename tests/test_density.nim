import
  std/[importutils, math, os, tables],
  bumpy, pixie, vmath,
  silky

const
  FontPath = "tests/data/IBMPlexSans-Regular.ttf"
  Glyphs = @[" ", "A", "V", "W", "g", "j", "@"]

proc close(a, b: float32): bool =
  ## Compares font metrics with a small floating point tolerance.
  abs(a - b) < 0.001

proc overlaps(a, b: Entry): bool =
  ## Returns whether two physical atlas rectangles share pixels.
  a.x < b.x + b.width and b.x < a.x + a.width and
    a.y < b.y + b.height and b.y < a.y + a.height

proc newTextFixture(builder: AtlasBuilder, density: float32): Silky =
  ## Queues native glyph vertices without creating a window or GPU.
  privateAccess(Silky)
  result = Silky(
    atlas: builder.atlas,
    image: builder.atlasImage,
    uiScale: density,
    inFrame: true
  )
  new(result.drawer)
  result.pushLayout(vec2(0, 0), vec2(300, 200))
  result.pushClipRect(rect(0, 0, 300, 200))

proc entryAt(font: FontAtlas, uv: Vec2): LetterEntry =
  ## Finds the exact atlas variant emitted by the native renderer.
  for variants in font.entries.values:
    for entry in variants:
      if uv == vec2(entry.x.float32, entry.y.float32):
        return entry
  doAssert false, "No glyph at texture coordinate " & $uv

proc assertPixelQuads(sk: Silky) =
  ## Requires each glyph texel to cover exactly one framebuffer pixel.
  let vertices = sk.drawer.layers[NormalLayer]
  doAssert vertices.len > 0
  doAssert vertices.len mod 6 == 0
  for vertex in vertices:
    let pixel = vertex.pos * sk.uiScale
    doAssert close(pixel.x, round(pixel.x)), $pixel
    doAssert close(pixel.y, round(pixel.y)), $pixel
    doAssert close(vertex.uv.x, round(vertex.uv.x))
    doAssert close(vertex.uv.y, round(vertex.uv.y))
  for i in countup(0, vertices.high, 6):
    let
      physical = (vertices[i + 2].pos - vertices[i].pos) * sk.uiScale
      texture = vertices[i + 2].uv - vertices[i].uv
    doAssert close(physical.x, texture.x), $physical & " != " & $texture
    doAssert close(physical.y, texture.y), $physical & " != " & $texture

block:
  echo "Testing exact-scale font rasterization and native text vertices"
  let regular = newAtlasBuilder(256, 2)
  regular.addFont(FontPath, "Default", 17, Glyphs)
  let reference = regular.atlas.fonts["Default"]
  for density in [0.75'f, 1.0'f, 1.25'f, 1.5'f, 2.0'f]:
    for steps in [0, 10]:
      let builder = newAtlasBuilder(512, 2)
      builder.addFont(
        FontPath,
        "Default",
        17,
        Glyphs,
        subpixelSteps = steps,
        pixelScale = density
      )
      let
        font = builder.atlas.fonts["Default"]
        sk = newTextFixture(builder, density)
        origin = vec2(10.17, 20.29)
        height = 100.0'f
      doAssert font.pixelScale == density
      doAssert close(font.size, reference.size)
      doAssert close(font.ascent, reference.ascent)
      doAssert close(font.descent, reference.descent)
      doAssert close(font.lineHeight, reference.lineHeight)
      for glyph in Glyphs:
        let
          entry = font.entries[glyph][0]
          expected = reference.entries[glyph][0]
        doAssert close(entry.advance, expected.advance), glyph
        for next, adjustment in expected.kerning:
          doAssert close(entry.kerning[next], adjustment), glyph & next
      for horizontal in [LeftAlign, CenterAlign, RightAlign]:
        for vertical in [TopAlign, MiddleAlign, BottomAlign]:
          sk.drawer.layers[NormalLayer].setLen(0)
          discard sk.drawText(
            "Default",
            "AVWgj@\n@jgWVA",
            origin,
            rgbx(255, 255, 255, 255),
            maxWidth = 240,
            maxHeight = height,
            hAlign = horizontal,
            vAlign = vertical
          )
          sk.assertPixelQuads()
          let
            vertices = sk.drawer.layers[NormalLayer]
            extra = height - font.lineHeight * 2
            alignment =
              case vertical
              of TopAlign:
                0.0'f
              of MiddleAlign:
                floor(extra * 0.5 * density)
              of BottomAlign:
                floor(extra * density)
          doAssert vertices.len == 12 * 6
          for i in 0 ..< 12:
            let
              vertex = vertices[i * 6]
              entry = font.entryAt(vertex.uv)
              baseline = (vertex.pos.y - entry.boundsY) * density
              expected = round(
                (origin.y + font.ascent + (i div 6).float32 *
                  font.lineHeight) * density
              ) + alignment
            doAssert close(baseline, expected),
              "Glyphs must share the line baseline: " & $baseline &
              " != " & $expected

      echo "Testing deferred text placement at scale ", density
      sk.drawer.layers[NormalLayer].setLen(0)
      let span = sk.beginVertexSpan()
      discard sk.drawText(
        "Default", "AVWgj@", origin, rgbx(255, 255, 255, 255)
      )
      sk.endVertexSpan(span, vec2(3.17, 4.29))
      sk.assertPixelQuads()
      sk.translateVertices(NormalLayer, 0, vec2(1.39, -2.13))
      sk.assertPixelQuads()
      var baseline = 0.0'f
      for i in 0 ..< 6:
        let
          vertex = sk.drawer.layers[NormalLayer][i * 6]
          entry = font.entryAt(vertex.uv)
          current = (vertex.pos.y - entry.boundsY) * density
        if i == 0:
          baseline = current
        doAssert close(current, baseline)
      sk.popClipRect()
      sk.popLayout()

      if steps == 0:
        let path = "tests/dist/fractional_density.png"
        builder.write(path)
        let loaded = readAtlas(path).atlas.fonts["Default"]
        doAssert loaded.pixelScale == density
        doAssert loaded.entries == font.entries

block:
  echo "Testing dense fonts preserve logical layout metrics"
  let
    regular = newAtlasBuilder(256, 2)
    dense = newAtlasBuilder(256, 2)
  regular.addFont(FontPath, "Default", 17, Glyphs)
  dense.addFont(FontPath, "Default", 17, Glyphs, pixelScale = 2)
  let
    regularFont = regular.atlas.fonts["Default"]
    denseFont = dense.atlas.fonts["Default"]
  doAssert regularFont.pixelScale == 1
  doAssert denseFont.pixelScale == 2
  doAssert close(regularFont.size, denseFont.size)
  doAssert close(regularFont.ascent, denseFont.ascent)
  doAssert close(regularFont.descent, denseFont.descent)
  doAssert close(regularFont.lineHeight, denseFont.lineHeight)
  doAssert close(regularFont.lineGap, denseFont.lineGap)
  for glyph in Glyphs:
    let
      regularEntry = regularFont.entries[glyph][0]
      denseEntry = denseFont.entries[glyph][0]
    doAssert close(regularEntry.advance, denseEntry.advance), glyph
    doAssert abs(regularEntry.boundsX - denseEntry.boundsX) <= 0.5
    doAssert abs(regularEntry.boundsY - denseEntry.boundsY) <= 0.5
    doAssert abs(regularEntry.boundsWidth - denseEntry.boundsWidth) <= 1
    doAssert abs(regularEntry.boundsHeight - denseEntry.boundsHeight) <= 1
    doAssert close(
      denseEntry.boundsWidth * 2,
      round(denseEntry.boundsWidth * 2)
    )
    doAssert close(
      denseEntry.boundsHeight * 2,
      round(denseEntry.boundsHeight * 2)
    )
    for next, adjustment in regularEntry.kerning:
      doAssert close(adjustment, denseEntry.kerning[next])
  doAssert denseFont.entries["A"][0].boundsHeight * 2 >
    regularFont.entries["A"][0].boundsHeight

  echo "Testing density survives embedded PNG metadata"
  let path = "tests/dist/density.png"
  doAssert dense.addImage("icon", newImage(48, 24), pixelScale = 2)
  dense.write(path)
  let loaded = readAtlas(path)
  doAssert loaded.atlas.entries["icon"].pixelScale == 2
  doAssert loaded.atlas.entries["icon"].width == 48
  doAssert loaded.atlas.entries["icon"].height == 24
  doAssert loaded.atlas.fonts["Default"].pixelScale == 2
  doAssert close(
    loaded.atlas.fonts["Default"].lineHeight,
    regularFont.lineHeight
  )
  doAssert loaded.atlas.fonts["Default"].entries["A"][0] ==
    denseFont.entries["A"][0]

block:
  echo "Testing directory images retain their density"
  let
    directory = "tests/dist/density_images/"
    builder = newAtlasBuilder(128, 2)
  createDir(directory)
  newImage(40, 24).writeFile(directory & "icon.png")
  builder.addDir(directory, directory, pixelScale = 2)
  let entry = builder.atlas.entries["icon"]
  doAssert entry.pixelScale == 2
  doAssert entry.width == 40 and entry.height == 24

block:
  echo "Testing live packing reserves full dense glyph rectangles"
  let builder = newAtlasBuilder(128, 1)
  builder.addFont(FontPath, "Default", 24, Glyphs, pixelScale = 2)
  let
    live = newAtlasBuilderFromAtlas(builder.atlas, builder.atlasImage)
    tile = newImage(5, 5)
  var added = 0
  for i in 0 ..< 1024:
    let name = "tile" & $i
    if not live.addImage(name, tile):
      break
    inc added
    let entry = live.atlas.entries[name]
    for font in live.atlas.fonts.values:
      for variants in font.entries.values:
        for glyph in variants:
          let bounds = Entry(
            x: glyph.x,
            y: glyph.y,
            width: round(glyph.boundsWidth * font.pixelScale.float32).int,
            height: round(glyph.boundsHeight * font.pixelScale.float32).int
          )
          if bounds.width > 0 and bounds.height > 0:
            doAssert not overlaps(entry, bounds), name & " overlaps a glyph"
  doAssert added > 0
  doAssert added < 1024

block:
  echo "Testing native image and patch coordinates at two densities"
  for density in 1 .. 2:
    let
      builder = newAtlasBuilder(128, 2)
      sk = Silky(atlas: builder.atlas, image: builder.atlasImage)
      position = vec2(12, 20)
    doAssert builder.addImage(
      "patch",
      newImage(32 * density, 32 * density),
      pixelScale = density
    )
    new(sk.drawer)
    sk.uiScale = density.float32
    sk.pushLayout(vec2(0, 0), vec2(300, 200))
    sk.pushClipRect(rect(0, 0, 300, 200))
    let
      entry = builder.atlas.entries["patch"]
      uv = vec2(entry.x.float32, entry.y.float32)
    doAssert sk.getImageSize("patch") == vec2(32, 32)
    sk.drawImage("patch", position)
    doAssert sk.drawer.layers[NormalLayer].len == 6
    doAssert sk.drawer.layers[NormalLayer][0].pos == position
    doAssert sk.drawer.layers[NormalLayer][2].pos == position + vec2(32)
    doAssert sk.drawer.layers[NormalLayer][0].uv == uv
    doAssert sk.drawer.layers[NormalLayer][2].uv ==
      uv + vec2((32 * density).float32)

    sk.drawer.layers[NormalLayer].setLen(0)
    sk.draw9Patch("patch", 4, position, vec2(100, 60))
    doAssert sk.drawer.layers[NormalLayer].len == 54
    for i in countup(0, 48, 6):
      let
        first = sk.drawer.layers[NormalLayer][i]
        last = sk.drawer.layers[NormalLayer][i + 2]
        destination = last.pos - first.pos
        source = last.uv - first.uv
      doAssert first.pos.x >= position.x
      doAssert first.pos.y >= position.y
      doAssert last.pos.x <= position.x + 100
      doAssert last.pos.y <= position.y + 60
      if i < 24:
        doAssert destination == vec2(4)
        doAssert source == vec2((4 * density).float32)
    if density == 2:
      for displayScale in [1.0'f, 1.5'f, 2.0'f]:
        sk.uiScale = displayScale
        sk.drawer.layers[NormalLayer].setLen(0)
        sk.drawImage("patch", vec2(12.2, 20.3))
        let origin = sk.drawer.layers[NormalLayer][0].pos * displayScale
        doAssert close(origin.x, round(origin.x))
        doAssert close(origin.y, round(origin.y))
        sk.drawer.layers[NormalLayer].setLen(0)
        sk.draw9Patch("patch", 4, vec2(12.2, 20.3), vec2(100.3, 60.2))
        for vertex in sk.drawer.layers[NormalLayer]:
          let pixel = vertex.pos * displayScale
          doAssert close(pixel.x, round(pixel.x))
          doAssert close(pixel.y, round(pixel.y))
    sk.popClipRect()
    sk.popLayout()

echo "All density tests passed."
