import
  std/[os, strutils, tables, unicode],
  pixie, jsony, vmath,
  allocator

const
  WhiteTileKey* = "_white_tile_"
  AsciiGlyphs* = static:
    var arr: seq[string]
    for c in " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~":
      arr.add($c)
    arr

type
  Entry* = object
    ## The position and size of a sprite in the atlas.
    x*: int
    y*: int
    width*: int
    height*: int

  LetterEntry* = object
    ## The position and size of a letter in the font atlas.
    x*: int
    y*: int
    boundsX*: float32
    boundsY*: float32
    boundsWidth*: float32
    boundsHeight*: float32
    advance*: float32
    kerning*: Table[string, float32]

  FontAtlas* = ref object
    ## The font atlas that is used to draw text.
    size*: float32
    entries*: Table[string, LetterEntry]

  SilkyAtlas* = ref object
    ## The pixel atlas that gets converted to JSON.
    size*: int
    entries*: Table[string, Entry]
    fonts*: Table[string, FontAtlas]

  AtlasBuilder* = ref object
    size: int
    margin: int
    dirs: seq[tuple[path: string, removePrefix: string]]
    fonts: seq[tuple[path: string, name: string, size: float32, chars: seq[string]]]

proc newAtlasBuilder*(size, margin: int): AtlasBuilder =
  AtlasBuilder(size: size, margin: margin)

proc addDir*(builder: AtlasBuilder, path: string, removePrefix: string = "") =
  builder.dirs.add((path, removePrefix))

proc addFont*(builder: AtlasBuilder, path: string, name: string, size: float32, chars: seq[string] = AsciiGlyphs) =
  builder.fonts.add((path, name, size, chars))

proc build*(builder: AtlasBuilder, outputImagePath, outputJsonPath: string) =
  ## Generates a pixel atlas from the given directories.
  let atlasImage = newImage(builder.size, builder.size)
  let atlas = SilkyAtlas(size: builder.size)
  let allocator = newSkylineAllocator(builder.size, builder.margin)

  # Always add black white tile to the atlas.
  let whiteTile = newImage(16, 16)
  whiteTile.fill(color(1, 1, 1, 1))
  let allocation = allocator.allocate(whiteTile.width, whiteTile.height)
  if allocation.success:
    atlasImage.draw(whiteTile, translate(vec2(allocation.x.float32, allocation.y.float32)), OverwriteBlend)
    atlas.entries[WhiteTileKey] = Entry(
      x: allocation.x,
      y: allocation.y,
      width: whiteTile.width,
      height: whiteTile.height
    )

  for dir in builder.dirs:
    for file in walkDir(dir.path):
      if file.path.endsWith(".png"):
        let image = readImage(file.path)
        let allocation = allocator.allocate(image.width, image.height)
        if allocation.success:
          atlasImage.draw(
            image,
            translate(vec2(allocation.x.float32, allocation.y.float32)),
            OverwriteBlend
          )
        else:
          raise newException(
            ValueError,
            "Failed to allocate space for " & file.path & "\n" &
            "You need to increase the size of the atlas"
          )
        let entry = Entry(
          x: allocation.x,
          y: allocation.y,
          width: image.width,
          height: image.height
        )
        var key = file.path.replace("\\", "/")
        if dir.removePrefix.len > 0:
          key.removePrefix(dir.removePrefix)
        key.removeSuffix(".png")
        atlas.entries[key] = entry
  
  for font in builder.fonts:
    # Read each glyph from the font and add it to the atlas.
    # Add advance as well
    echo "Reading font: ", font.path
    let fontAtlas = FontAtlas()
    fontAtlas.size = font.size
    let typeface = readTypeface(font.path)
    var fontObj = newFont(typeface)
    fontObj.size = font.size

    for glyphStr in font.chars:
      let rune = glyphStr.runeAt(0)
      let path = typeface.getGlyphPath(rune)
      let scale = fontObj.scale
      let scaleMat = scale(vec2(scale))
      let bounds = path.computeBounds(scaleMat).snapToPixels()
      # echo "  Glyph: ", glyphStr, " ", rune, " ", bounds.w, "x", bounds.h
      if bounds.w.ceil.int > 0 and bounds.h.ceil.int > 0:
        let glyphImage = newImage(bounds.w.ceil.int, bounds.h.ceil.int)
        glyphImage.fillPath(
          path,
          color(1, 1, 1, 1),
          translate(-bounds.xy) * scaleMat
        )
        let allocation = allocator.allocate(glyphImage.width, glyphImage.height)
        if not allocation.success:
          raise newException(
            ValueError,
            "Failed to allocate space for glyph: " & glyphStr & "\n" &
            "You need to increase the size of the atlas"
          )
        atlasImage.draw(
          glyphImage,
          translate(vec2(allocation.x.float32, allocation.y.float32)),
          OverwriteBlend
        )
        fontAtlas.entries[glyphStr] = LetterEntry(
          x: allocation.x,
          y: allocation.y,
          boundsX: bounds.x,
          boundsY: bounds.y,
          boundsWidth: bounds.w,
          boundsHeight: bounds.h,
          advance: typeface.getAdvance(rune) * scale
        )
      else:
        # Probably a space of some sort, still has advance, so we can use it.
        fontAtlas.entries[glyphStr] = LetterEntry(
          x: 0,
          y: 0,
          boundsX: bounds.x,
          boundsY: bounds.y,
          boundsWidth: bounds.w,
          boundsHeight: bounds.h,
          advance: typeface.getAdvance(rune) * scale
        )
      for glyphStr2 in font.chars:
        let rune2 = glyphStr2.runeAt(0)
        let kerning = typeface.getKerningAdjustment(rune, rune2)
        if kerning != 0:
          fontAtlas.entries[glyphStr].kerning[glyphStr2] = kerning * scale
    atlas.fonts[font.name] = fontAtlas

  atlasImage.writeFile(outputImagePath)
  writeFile(outputJsonPath, atlas.toJson())

