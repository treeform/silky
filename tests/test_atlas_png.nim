## Tests for atlas JSON embedded inside PNG files.

import
  std/[math, os, tables],
  pixie,
  silky/[allocator, atlas]

proc assertRaisesMissingChunk(path: string) =
  ## Asserts that reading metadata fails when chunk is missing.
  var raised = false
  try:
    discard extractAtlasJsonFromPng(readFile(path))
  except SilkyAtlasError:
    raised = true
  doAssert raised, "Expected missing atlas metadata exception"

block:
  echo "Testing atlas builder single-file PNG output"
  let
    outputPath = "tests/dist/atlas_embedded.png"
    builder = newAtlasBuilder(64, 2)
  builder.write(outputPath)
  let loadedAtlasData = readAtlas(outputPath)
  doAssert loadedAtlasData.atlas != nil
  doAssert WhiteTileKey in loadedAtlasData.atlas.entries
  doAssert loadedAtlasData.image.width == builder.size
  doAssert loadedAtlasData.image.height == builder.size

block:
  echo "Testing direct writePng and metadata roundtrip"
  let
    path = "tests/dist/atlas_custom_chunk.png"
    json = """{"tag":"hello","count":3}"""
    image = newImage(8, 8)
  image.fill(color(1, 0, 0, 1))
  writePng(path, json, image)
  let extracted = extractAtlasJsonFromPng(readFile(path))
  doAssert extracted == json
  let decoded = readImage(path)
  doAssert decoded.width == 8
  doAssert decoded.height == 8

block:
  echo "Testing failure when metadata chunk is missing"
  let
    path = "tests/dist/plain.png"
    image = newImage(4, 4)
  image.fill(color(0, 1, 0, 1))
  createDir(path.splitPath().head)
  image.writeFile(path)
  assertRaisesMissingChunk(path)

block:
  echo "Testing glyphs with no outline get finite bounds"
  # A space has no path, so pixie reports infinite/NaN bounds for it. Those
  # used to reach the atlas and stop text layout at the first space.
  const Finite = {fcNormal, fcSubnormal, fcZero, fcNegZero}
  let builder = newAtlasBuilder(256, 2)
  builder.addFont("tests/data/IBMPlexSans-Regular.ttf", "Default", 16.0)
  let entry = builder.atlas.fonts["Default"].entries[" "][0]
  doAssert entry.boundsX.classify in Finite, $entry.boundsX
  doAssert entry.boundsY.classify in Finite, $entry.boundsY
  doAssert entry.boundsWidth.classify in Finite, $entry.boundsWidth
  doAssert entry.boundsHeight.classify in Finite, $entry.boundsHeight
  doAssert entry.advance > 0, $entry.advance

proc overlaps(a, b: Entry): bool =
  ## True when two atlas entries share any pixels.
  a.x < b.x + b.width and b.x < a.x + a.width and
    a.y < b.y + b.height and b.y < a.y + a.height

block:
  echo "Testing markRegion never lowers the skyline"
  let allocator = newSkylineAllocator(64, 0)
  allocator.markRegion(0, 0, 64, 32)
  allocator.markRegion(0, 0, 64, 8)
  let allocation = allocator.allocate(8, 8)
  doAssert allocation.success
  doAssert allocation.y >= 32, $allocation

block:
  echo "Testing markRegion raises only the covered columns"
  let allocator = newSkylineAllocator(64, 0)
  allocator.markRegion(0, 0, 32, 16)
  allocator.markRegion(16, 0, 32, 8)
  # Columns 0..47 are covered up to y 16 or 8, columns 48..63 are free.
  let free = allocator.allocate(16, 16)
  doAssert free.success
  doAssert free.x == 48 and free.y == 0, $free
  let wide = allocator.allocate(48, 4)
  doAssert wide.success
  doAssert wide.y >= 16, $wide

block:
  echo "Testing live builder does not pack over existing entries"
  let builder = newAtlasBuilder(64, 1)
  doAssert builder.addImage("a", newImage(60, 10))
  doAssert builder.addImage("b", newImage(60, 10))
  let live = newAtlasBuilderFromAtlas(builder.atlas, builder.atlasImage)
  doAssert live.addImage("new", newImage(60, 10))
  let added = live.atlas.entries["new"]
  for name, entry in live.atlas.entries:
    if name != "new":
      doAssert not overlaps(added, entry), name & " " & $entry & " " & $added

echo "All atlas PNG tests passed."
