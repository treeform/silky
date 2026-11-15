import
  std/[json, math, os, tables, tempfiles, unicode],
  pixie, jsony,
  silky/atlas

const
  FontPath = "tests/data/IBMPlexSans-Regular.ttf"
  Glyphs = @["A", "V", "g", " "]

proc overlaps(a, b: Entry): bool =
  ## Returns whether two atlas rectangles share pixels.
  a.x < b.x + b.width and b.x < a.x + a.width and
    a.y < b.y + b.height and b.y < a.y + a.height

proc checkRetinaAtlas() =
  ## Checks physical raster density without changing logical font layout.
  let builder = newAtlasBuilder(512, 2)
  builder.addFont(FontPath, "1x", 18, Glyphs)
  builder.addFont(FontPath, "2x", 18, Glyphs, pixelScale = 2)
  builder.addFont(FontPath, "3x", 18, Glyphs, pixelScale = 3)
  builder.addFont(FontPath, "54px", 54, Glyphs)
  let
    base = builder.atlas.fonts["1x"]
    retina = builder.atlas.fonts["3x"]
    large = builder.atlas.fonts["54px"]
  for name in ["2x", "3x"]:
    let font = builder.atlas.fonts[name]
    doAssert font.size == base.size
    doAssert font.ascent == base.ascent
    doAssert font.descent == base.descent
    doAssert font.lineHeight == base.lineHeight
    doAssert font.lineGap == base.lineGap
    for glyph in Glyphs:
      let
        normal = base.entries[glyph][0]
        dense = font.entries[glyph][0]
      doAssert dense.advance == normal.advance
      doAssert dense.kerning == normal.kerning
      doAssert abs(dense.boundsWidth - normal.boundsWidth) <= 1
      doAssert abs(dense.boundsHeight - normal.boundsHeight) <= 1

  doAssert retina.lookupKerning(Rune('A'), Rune('V')) ==
    base.lookupKerning(Rune('A'), Rune('V'))
  for glyph in Glyphs:
    let
      dense = retina.entries[glyph][0]
      physical = large.entries[glyph][0]
      width = round(dense.boundsWidth * retina.rasterScale).int
      height = round(dense.boundsHeight * retina.rasterScale).int
    doAssert width == physical.boundsWidth.int
    doAssert height == physical.boundsHeight.int
    doAssert abs(dense.boundsX * 3 - physical.boundsX) < 0.0001
    doAssert abs(dense.boundsY * 3 - physical.boundsY) < 0.0001
    for y in 0 ..< height:
      for x in 0 ..< width:
        doAssert builder.atlasImage[dense.x + x, dense.y + y] ==
          builder.atlasImage[physical.x + x, physical.y + y]

  let directory = createTempDir("silky-retina-", "")
  defer: removeDir(directory)
  let path = directory / "atlas.png"
  builder.write(path)
  let loaded = readAtlas(path)
  doAssert loaded.atlas.fonts["3x"].rasterScale == 3
  doAssert loaded.atlas.fonts["3x"].size == 18
  doAssert loaded.atlas.fonts["3x"].lookupKerning(Rune('A'), Rune('V')) ==
    retina.lookupKerning(Rune('A'), Rune('V'))

  let live = newAtlasBuilderFromAtlas(loaded.atlas, loaded.image, 2)
  for i in 0 ..< 12:
    let name = "new" & $i
    doAssert live.addImage(name, newImage(28, 16))
    let added = live.atlas.entries[name]
    for font in live.atlas.fonts.values:
      for variants in font.entries.values:
        for glyph in variants:
          let occupied = Entry(
            x: glyph.x,
            y: glyph.y,
            width: round(glyph.boundsWidth * font.rasterScale).int,
            height: round(glyph.boundsHeight * font.rasterScale).int
          )
          if occupied.width > 0 and occupied.height > 0:
            doAssert not overlaps(added, occupied)

  let
    legacy = newAtlasBuilder(128, 2)
    legacyPath = directory / "legacy.png"
  legacy.addFont(FontPath, "Default", 18, Glyphs)
  var metadata = parseJson(legacy.atlas.toJson())
  metadata["fonts"]["Default"].delete("pixelScale")
  writePng(legacyPath, $metadata, legacy.atlasImage)
  let oldFont = readAtlasFromPng(legacyPath).fonts["Default"]
  doAssert oldFont.rasterScale == 1
  doAssert oldFont.entries["A"][0] == legacy.atlas.fonts["Default"].entries["A"][0]
  doAssert FontAtlas().rasterScale == 1

  let subpixel = newAtlasBuilder(512, 2)
  subpixel.addFont(FontPath, "3x", 18, @["A"], 4, 3)
  let variants = subpixel.atlas.fonts["3x"].entries["A"]
  doAssert variants.len == 4
  doAssert abs(variants[1].boundsWidth - variants[0].boundsWidth - 1.0 / 3) < 0.0001
  doAssert variants[1].advance == variants[0].advance

  for invalid in [0.0'f, -1.0'f, Inf.float32, NaN.float32]:
    var rejected = false
    try:
      builder.addFont(FontPath, "Invalid", 18, Glyphs, pixelScale = invalid)
    except SilkyAtlasError:
      rejected = true
    doAssert rejected

checkRetinaAtlas()
echo "Retina atlas metrics, pixels, roundtrip and packing tests passed."
