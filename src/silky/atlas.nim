import
  std/[os, strutils, tables, unicode],
  pixie, jsony, vmath, crunchy,
  pixie/fileformats/png,
  flatty/binny,
  allocator

const
  WhiteTileKey* = "_white_tile_"
  AtlasJsonChunkType* = "siAT"
  AsciiGlyphs* = static:
    var arr: seq[string]
    for c in " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~":
      arr.add($c)
    arr

type
  SilkyAtlasError* = object of CatchableError
    ## Raised when atlas PNG metadata cannot be encoded or decoded.

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

  GlyphEntries* = ref object
    ## Runtime reference to the stored variants for one glyph.
    entries*: seq[LetterEntry]

  GlyphLookup* = object
    ## Runtime lookup tables for allocation-free Unicode text rendering.
    entries*: Table[Rune, GlyphEntries]
    kerning*: Table[uint64, float32]

  FontAtlas* = ref object
    ## The font atlas that is used to draw text.
    size*: float32
    lineHeight*: float32
    descent*: float32
    ascent*: float32
    lineGap*: float32
    subpixelSteps*: int
    entries*: Table[string, seq[LetterEntry]]
    lookup*: GlyphLookup

  SilkyAtlas* = ref object
    ## The pixel atlas that gets converted to JSON.
    size*: int
    entries*: Table[string, Entry]
    fonts*: Table[string, FontAtlas]

  AtlasBuilder* = ref object
    ## Use to build a pixel atlas from a given directories, fonts, and images.
    size*: int
    margin*: int
    allocator*: SkylineAllocator
    atlasImage*: Image
    atlas*: SilkyAtlas

  FontAtlasObject = typeof(FontAtlas()[])

proc skipHook*(T: typedesc[FontAtlasObject], key: static string): bool =
  ## Skips runtime-only lookup tables during atlas JSON serialization.
  key == "lookup"

proc kerningKey(left, right: Rune): uint64 {.inline.} =
  ## Packs two Unicode scalar values into one table key.
  (uint64(uint32(int32(left))) shl 32) or uint64(uint32(int32(right)))

proc rebuildGlyphLookups*(fontAtlas: FontAtlas) =
  ## Rebuilds runtime Unicode lookup tables from serialized atlas entries.
  fontAtlas.lookup.entries = initTable[Rune, GlyphEntries](
    fontAtlas.entries.len
  )
  fontAtlas.lookup.kerning = initTable[uint64, float32]()

  for glyphStr, entries in fontAtlas.entries:
    if glyphStr.len == 0:
      continue
    let left = glyphStr.runeAt(0)
    fontAtlas.lookup.entries[left] = GlyphEntries(entries: entries)
    if entries.len == 0:
      continue
    for rightStr, adjustment in entries[0].kerning:
      if rightStr.len == 0:
        continue
      let right = rightStr.runeAt(0)
      fontAtlas.lookup.kerning[kerningKey(left, right)] = adjustment

proc rebuildGlyphLookups*(atlas: SilkyAtlas) =
  ## Rebuilds runtime text lookup tables for every font in an atlas.
  for fontAtlas in atlas.fonts.mvalues:
    fontAtlas.rebuildGlyphLookups()

proc lookupLetter*(
  fontAtlas: FontAtlas,
  rune: Rune,
  variant: int,
  entry: var ptr LetterEntry
): bool {.inline.} =
  ## Looks up one glyph entry without allocating a string key.
  if rune in fontAtlas.lookup.entries:
    let glyphEntries = fontAtlas.lookup.entries[rune]
    if glyphEntries.entries.len > 0:
      entry = unsafeAddr glyphEntries.entries[
        min(variant, glyphEntries.entries.len - 1)
      ]
      return true

  let fallback = Rune(63)
  if fallback in fontAtlas.lookup.entries:
    let glyphEntries = fontAtlas.lookup.entries[fallback]
    if glyphEntries.entries.len > 0:
      entry = unsafeAddr glyphEntries.entries[0]
      return true

  false

proc lookupKerning*(fontAtlas: FontAtlas, left, right: Rune): float32 {.inline.} =
  ## Looks up kerning between two glyphs without allocating string keys.
  fontAtlas.lookup.kerning.getOrDefault(kerningKey(left, right))

proc newAtlasBuilder*(size, margin: int): AtlasBuilder =
  ## Generate a pixel atlas from the given directories.
  let
    atlasImage = newImage(size, size)
    atlas = SilkyAtlas(size: size)
    allocator = newSkylineAllocator(size, margin)

  # Always add a pure white square to the atlas.
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

  result = AtlasBuilder(
    size: size,
    margin: margin,
    allocator: allocator,
    atlasImage: atlasImage,
    atlas: atlas
  )

proc addPngChunk(buffer: var string, chunkType, chunkData: string) =
  ## Appends one PNG chunk to the output buffer.
  buffer.addUint32(chunkData.len.uint32.swap())
  buffer.add(chunkType)
  buffer.add(chunkData)
  let chunkStart = buffer.len - (chunkData.len + 4)
  buffer.addUint32(crc32(
    buffer[chunkStart].addr,
    chunkData.len + 4
  ).swap())

proc validatePngSignature(data: string) =
  ## Validates PNG magic bytes.
  if data.len < 8:
    raise newException(SilkyAtlasError, "Invalid PNG data: missing signature")
  let signature = cast[array[8, uint8]](data.readUint64(0))
  if signature != pngSignature:
    raise newException(SilkyAtlasError, "Invalid PNG data: bad signature")

proc eachPngChunk(
  data: string,
  fn: proc(chunkType, chunkData: string, chunkStart, nextStart: int): bool
) =
  ## Iterates PNG chunks and validates chunk bounds and CRC.
  validatePngSignature(data)
  var pos = 8
  while pos < data.len:
    if pos + 8 > data.len:
      raise newException(SilkyAtlasError, "Invalid PNG data: truncated chunk header")
    let
      chunkLen = data.readUint32(pos).swap().int
      chunkType = data.readStr(pos + 4, 4)
      chunkDataStart = pos + 8
      chunkDataEnd = chunkDataStart + chunkLen
      crcStart = chunkDataEnd
      nextStart = crcStart + 4
    if chunkLen < 0:
      raise newException(SilkyAtlasError, "Invalid PNG data: negative chunk size")
    if nextStart > data.len:
      raise newException(SilkyAtlasError, "Invalid PNG data: truncated chunk data")
    let expected = crc32(data[pos + 4].addr, chunkLen + 4)
    let found = data.readUint32(crcStart).swap()
    if expected != found:
      raise newException(SilkyAtlasError, "Invalid PNG data: CRC mismatch")
    let chunkData = data.readStr(chunkDataStart, chunkLen)
    let stop = fn(chunkType, chunkData, pos, nextStart)
    if stop:
      return
    pos = nextStart
  raise newException(SilkyAtlasError, "Invalid PNG data: missing IEND")

proc embedAtlasJsonInPng*(pngData, atlasJson: string): string =
  ## Embeds atlas JSON in a custom PNG ancillary chunk.
  var iendStart = -1
  eachPngChunk(
    pngData,
    proc(chunkType, chunkData: string, chunkStart, nextStart: int): bool =
      if chunkType == "IEND":
        iendStart = chunkStart
        return true
      false
  )
  if iendStart < 0:
    raise newException(SilkyAtlasError, "Invalid PNG data: missing IEND")
  result = newStringOfCap(pngData.len + atlasJson.len + 12)
  result.add(pngData[0 ..< iendStart])
  result.addPngChunk(AtlasJsonChunkType, atlasJson)
  result.add(pngData[iendStart .. ^1])

proc extractAtlasJsonFromPng*(pngData: string): string =
  ## Extracts embedded atlas JSON from a PNG custom chunk.
  var
    atlasJson = ""
    found = false
    seenIend = false
  eachPngChunk(
    pngData,
    proc(chunkType, chunkData: string, chunkStart, nextStart: int): bool =
      if chunkType == AtlasJsonChunkType:
        atlasJson = chunkData
        found = true
      if chunkType == "IEND":
        seenIend = true
        return true
      false
  )
  if not seenIend:
    raise newException(SilkyAtlasError, "Invalid PNG data: missing IEND")
  if not found:
    raise newException(
      SilkyAtlasError,
      "Atlas PNG is missing embedded JSON metadata"
    )
  result = atlasJson

proc readAtlasFromPng*(path: string): SilkyAtlas =
  ## Reads and decodes the atlas JSON embedded in an atlas PNG file.
  try:
    result = extractAtlasJsonFromPng(readFile(path)).fromJson(SilkyAtlas)
    result.rebuildGlyphLookups()
  except IOError as e:
    raise newException(SilkyAtlasError, e.msg, e)

proc readAtlas*(
  path: string
): tuple[atlas: SilkyAtlas, image: Image] =
  ## Reads atlas metadata and image from one PNG file read.
  try:
    let pngData = readFile(path)
    result.atlas = extractAtlasJsonFromPng(pngData).fromJson(SilkyAtlas)
    result.atlas.rebuildGlyphLookups()
    result.image = decodePng(pngData).convertToImage()
  except IOError as e:
    raise newException(SilkyAtlasError, e.msg, e)

proc writePng*(path, json: string, image: Image) =
  ## Writes a PNG with embedded atlas JSON metadata.
  let dir = path.splitPath().head
  if dir.len > 0:
    createDir(dir)
  let encoded = image.encodeImage(PngFormat)
  let withMetadata = embedAtlasJsonInPng(encoded, json)
  try:
    writeFile(path, withMetadata)
  except IOError as e:
    raise newException(SilkyAtlasError, e.msg, e)

proc addDir*(builder: AtlasBuilder, path: string, removePrefix: string = "") =
  ## Add all images in the given directory to the atlas.
  for file in walkDir(path):
    if file.path.endsWith(".png"):
      let image = readImage(file.path)
      let allocation = builder.allocator.allocate(image.width, image.height)
      if allocation.success:
        builder.atlasImage.draw(
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
      if removePrefix.len > 0:
        key.removePrefix(removePrefix)
      key.removeSuffix(".png")
      builder.atlas.entries[key] = entry

proc addDirRecursive*(builder: AtlasBuilder, path: string, removePrefix: string = "") =
  ## Add all images in the given directory and its subdirectories to the atlas.
  builder.addDir(path, removePrefix)
  for entry in walkDir(path):
    if entry.kind == pcDir:
      builder.addDirRecursive(entry.path, removePrefix)

proc addFont*(builder: AtlasBuilder, path: string, name: string, size: float32, chars: seq[string] = AsciiGlyphs, subpixelSteps: int = 0) =
  ## Add a font to the atlas.
  let fontAtlas = FontAtlas()
  fontAtlas.size = size
  fontAtlas.subpixelSteps = subpixelSteps
  let typeface = readTypeface(path)
  var fontObj = newFont(typeface)
  fontObj.size = size
  fontAtlas.lineHeight = (typeface.ascent - typeface.descent + typeface.lineGap) * fontObj.scale
  fontAtlas.ascent = typeface.ascent * fontObj.scale
  fontAtlas.descent = typeface.descent * fontObj.scale
  fontAtlas.lineGap = typeface.lineGap * fontObj.scale
  # If subpixelSteps > 0, generates multiple versions of each glyph shifted by 1/subpixelSteps pixels.
  # For example, subpixelSteps=10 generates 10 versions per glyph at 0.0, 0.1, 0.2, ... 0.9 pixel offsets.
  let numVariants = if subpixelSteps > 0: subpixelSteps else: 1

  for glyphStr in chars:
    let
      rune = glyphStr.runeAt(0)
      glyphPath = typeface.getGlyphPath(rune)
      scale = fontObj.scale
      scaleMat = scale(vec2(scale))
      baseBounds = glyphPath.computeBounds(scaleMat).snapToPixels()
      advance = typeface.getAdvance(rune) * scale
    fontAtlas.entries[glyphStr] = @[]
    for variant in 0 ..< numVariants:
      let
        subpixelOffset =
          if subpixelSteps > 0:
            variant.float32 / subpixelSteps.float32
          else:
            0.0  # No subpixel support.
        offsetBounds = rect(
          baseBounds.x + subpixelOffset,
          baseBounds.y,
          baseBounds.w + (if subpixelOffset > 0: 1.0 else: 0.0),
          baseBounds.h
        )
      if offsetBounds.w.ceil.int > 0 and offsetBounds.h.ceil.int > 0:
        let glyphImage = newImage(offsetBounds.w.ceil.int, offsetBounds.h.ceil.int)
        glyphImage.fillPath(
          glyphPath,
          color(1, 1, 1, 1),
          translate(vec2(-baseBounds.x + subpixelOffset - subpixelOffset.floor, -baseBounds.y)) * scaleMat
        )
        let allocation = builder.allocator.allocate(glyphImage.width, glyphImage.height)
        if not allocation.success:
          raise newException(
            ValueError,
            "Failed to allocate space for glyph: " & glyphStr & " variant " & $variant & "\n" &
            "You need to increase the size of the atlas"
          )
        builder.atlasImage.draw(
          glyphImage,
          translate(vec2(allocation.x.float32, allocation.y.float32)),
          OverwriteBlend
        )
        fontAtlas.entries[glyphStr].add(LetterEntry(
          x: allocation.x,
          y: allocation.y,
          boundsX: baseBounds.x + subpixelOffset.floor,
          boundsY: baseBounds.y,
          boundsWidth: offsetBounds.w.ceil,
          boundsHeight: offsetBounds.h.ceil,
          advance: advance
        ))
      else:
        fontAtlas.entries[glyphStr].add(LetterEntry(
          x: 0,
          y: 0,
          boundsX: baseBounds.x,
          boundsY: baseBounds.y,
          boundsWidth: baseBounds.w,
          boundsHeight: baseBounds.h,
          advance: advance
        ))
    # Kerning only needs to be stored once per base glyph (variant 0).
    for glyphStr2 in chars:
      let rune2 = glyphStr2.runeAt(0)
      let kerning = typeface.getKerningAdjustment(rune, rune2)
      if kerning != 0:
        fontAtlas.entries[glyphStr][0].kerning[glyphStr2] = kerning * scale
  fontAtlas.rebuildGlyphLookups()
  builder.atlas.fonts[name] = fontAtlas

proc write*(builder: AtlasBuilder, outputPngPath: string) =
  ## Write atlas image and JSON metadata into a single PNG.
  writePng(outputPngPath, builder.atlas.toJson(), builder.atlasImage)
