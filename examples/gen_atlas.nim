import ../src/silky

generateAtlas(
  outputImagePath = "examples/dist/atlas.png",
  outputJsonPath = "examples/dist/atlas.json",
  size = 1024 * 2,
  margin = 4,
  dirsToScan = @["examples/data/", "examples/data/ui/", "examples/data/vibe/"],
  rmPrefix = "examples/data/"
)
