import ../src/silky

var builder = newAtlasBuilder(1024 * 2, 4)

builder.addDir("examples/data/", "examples/data/")
builder.addDir("examples/data/ui/", "examples/data/")
builder.addDir("examples/data/vibe/", "examples/data/")

builder.addFont("examples/data/IBMPlexMono-Bold.ttf", "IBMPlexMono-Bold", 100.0)

builder.build("examples/dist/atlas.png", "examples/dist/atlas.json")
