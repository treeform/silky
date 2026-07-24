# Silky - Fast UI for Nim.

Silky is an immediate mode GUI that focuses on speed above all else.

- Single draw call to render the entire UI
- A clean DSL to build interfaces that looks like idiomatic Nim
- 9-patch support for scalable UI elements
- Texture atlas for efficient rendering

It borrows many ideas from Dear ImGui, but it is not a direct port.

## Philosophy

I wanted something very, very fast. Dear ImGui is known to be one of the fastest GUI libraries out there. I studied Dear ImGui to understand *what* actually makes it fast. Why is it so performant?

But I didn't want to just use Dear ImGui directly. It's written in C++, a completely different language. I wanted to build something that feels more Nim-like — using templates that look the way Nim code is supposed to look.

So this is my reimplementation, or rather, reimagination of what an immediate mode GUI should look like in Nim.

I've written many other libraries like Pixie (2D graphics) and Windy (Windowing system). I wanted to use them as well because I believe they're high-quality software. But ultimately, I wanted to build my own GUI library to understand GUIs from the inside out.

## Getting Started

```nim
import silky

# Build the texture atlas
let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

# Create a window
let window = newWindow("My App", ivec2(800, 600), vsync = false)
makeContextCurrent(window)
loadExtensions()

# Create Silky instance
let sk = newSilky(window, "dist/atlas.png")

window.onFrame = proc() =
  sk.beginUI(window, window.size)

  ui:
    text "hello":
      characters "Hello Silky!"
    button "Click me":
      echo "Clicked!"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
```
To run this example, you'll need a `data` directory with a `button.9patch.png` file and an `IBMPlexSans-Regular.ttf` font file in it — both are available in the examples.

See [docs/porting.md](docs/porting.md) for moving older cursor-style Silky UI to this Fidget-style DSL.

## Supported APIs

Silky supports multiple graphics backends across platforms:

| | OpenGL | DirectX 12 | Vulkan 1.4 | Metal 4 | CPU | WebGL 2 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Windows** | ✅ | ✅ | ✅ | | ✅ | |
| **macOS** | ✅ | | | ✅ | | |
| **Linux** | ✅ | | | | | |
| **Emscripten/WASM** | | | | | | ✅ |

Compile with the appropriate flag to select a backend:

```
nim c app.nim                  # OpenGL (default)
nim c -d:useDirectX app.nim   # DirectX 12
nim c -d:useVulkan app.nim    # Vulkan 1.4
nim c -d:useMetal4 app.nim    # Metal 4
nim c -d:useCpu app.nim       # CPU rasterizer
nim c -d:emscripten app.nim   # WebGL 2 (Emscripten)
```

The CPU backend keeps the same Silky API, but rasterizes into a Pixie image and
presents it through Windy. It is currently intended for simple Windows testing
and bring-up work where a GPU backend is not available.

## Theming

Silky supports theming via the `theme` object:

```nim
sk.theme.defaultTextColor = parseHtmlColor("#2C3E50").rgbx
sk.theme.buttonHoverColor = rgbx(200, 200, 200, 255)
sk.theme.buttonDownColor = rgbx(180, 180, 180, 255)
sk.theme.frameFocusColor = parseHtmlColor("#D5DBDB").rgbx
```

## Profiling

Profile helpers stay in `silky/profiles` and are not re-exported from `import silky`.
Import them when you want runtime start/stop:

```nim
import silky/profiles

startRuntimeProfileTrace("tmp/perf.json")
# ... work measured by profileBlock / {.measure.} ...
discard finishProfileTrace()
# or:
discard toggleRuntimeProfileTrace("tmp/perf.json")
```

Compile-time static capture still works with `-d:ProfileTracePath=...` and
`-d:ProfileNumFrames=N`.

## License

MIT License
