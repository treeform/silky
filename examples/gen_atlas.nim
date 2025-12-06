import ../src/silky

var builder = newAtlasBuilder(1024 * 2, 4)

builder.addDir("examples/data/", "examples/data/")
builder.addDir("examples/data/ui/", "examples/data/")
builder.addDir("examples/data/vibe/", "examples/data/")

builder.addFont("examples/data/IBMPlexSans-Regular.ttf", "Title", 22.0)
builder.addFont("examples/data/IBMPlexSans-Regular.ttf", "Peragraph", 18.0)

builder.write("examples/dist/atlas.png", "examples/dist/atlas.json")
