import
  std/[os, strutils, tables, tempfiles],
  pixie,
  silky/atlas

block:
  echo "Testing atlas prefixes with native and mixed path separators"
  let directory = createTempDir("silky-atlas-paths-", "")
  defer:
    removeDir(directory)
  createDir(directory / "nested")
  newImage(8, 8).writeFile(directory / "close.png")
  newImage(4, 4).writeFile(directory / "nested" / "inside.png")
  for prefix in [
    directory & DirSep,
    directory.replace('\\', '/') & "/",
    directory.replace('/', '\\') & "\\"
  ]:
    let builder = newAtlasBuilder(64, 2)
    builder.addDir(directory, prefix, pixelScale = 2)
    doAssert "close" in builder.atlas.entries, prefix
    doAssert builder.atlas.entries.len == 2
    doAssert builder.atlas.entries["close"].pixelScale == 2
    let recursive = newAtlasBuilder(64, 2)
    recursive.addDirRecursive(directory, prefix)
    doAssert "close" in recursive.atlas.entries, prefix
    doAssert "nested/inside" in recursive.atlas.entries, prefix
    doAssert recursive.atlas.entries.len == 3

echo "Atlas path checks passed."
