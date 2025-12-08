import silky

var builder = newAtlasBuilder(1024, 4)

builder.addDir("data/", "data/")
builder.addDir("data/ui/", "data/")
builder.addDir("data/vibe/", "data/")

builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)

builder.write("dist/atlas.png", "dist/atlas.json")
