# Porting to the Fidget DSL

Silky still draws the same way under the hood. The Fidget-style DSL changes how you *author* UI: nested nodes with string ids instead of a cursor you nudge by hand.

The new style is usually easier to read. Hierarchy shows up in indentation, sizes and layout live next to the widgets they affect, and you spend less time chasing `sk.at` math. Widgets like `button` and `dropDown` keep the same call shape, so most ports are mechanical.

## Why switch

Old Silky is ImGui-shaped: draw at `sk.at`, then advance. That is fast to type for tiny UIs, but layout intent is easy to lose once you nest groups, overlap controls, or scroll.

```nim
# Old: cursor + manual offset
text("Two overlapping buttons:")
button("Behind"):
  behindClicked = true
sk.at = sk.at + overlap
button("In Front"):
  inFrontClicked = true
```

```nim
# New: nested structure
ui:
  text "label":
    characters "Two overlapping buttons:"
  group "buttons":
    box 200, 80
    # Prefer explicit boxes over sk.at hacks.
    button "Behind":
      behindClicked = true
    button "In Front":
      inFrontClicked = true
```

Same widgets, clearer tree.

## Frame lifecycle stays the same

Keep `beginUI` / `endUi`, themes, atlas, and low-level draws. Wrap authored UI in `ui:`:

```nim
sk.beginUI(window, window.size)

# Raw draws can stay outside ui:
sk.drawImage("testTexture", vec2(0, 0), rgbx(30, 30, 30, 255))

ui:
  # DSL and widgets go here
  text "hello":
    characters "Hello world!"

sk.endUi()
```

Outside `ui:`, old one-liners like `text("Hello")` still work. Inside `ui:`, those names prefer the DSL path.

## Common replacements

### Text

```nim
# Old
text("Hello world!")
h1text("Title")

# New
text "hello":
  characters "Hello world!"

text "title":
  characters "Title"
  font "H1"
  tint sk.theme.textH1Color

# Shorthand still works inside ui:
text "Hello world!"
h1text "Title"
```

Prefer an explicit id when the same label appears more than once. The shorthand `text "Hello"` uses id `"text:Hello"`.

### Groups and layout

```nim
# Old
group(vec2(10, 0), LeftToRight):
  button("A"): discard
  button("B"): discard

# New
group "row":
  box 200, 40
  layout LeftToRight
  itemSpacing 8
  button "A": discard
  button "B": discard
```

`box w, h` sizes from the current cursor. `box x, y, w, h` is parent-relative.

### Frames

```nim
# Old scrollable frame (absolute pos/size)
frame("myList", sk.at, vec2(200, 100)):
  text("item")

# New
frame "myList":
  box 200, 100
  text "item":
    characters "item"

# Compatibility overload still accepts absolute pos/size:
frame("myList", sk.at, vec2(200, 100)):
  text "item":
    characters "item"
```

`frame` nodes clip and scroll by default (`frame.9patch`). For a simple non-scrolling panel, set the patch yourself:

```nim
frame "stats":
  box 10, 200, 220, 180
  patch "window.9patch", 14
```

| | `group` | `frame` |
|---|---|---|
| Scrollbars | No | Yes when content overflows |
| Default patch | None | `frame.9patch` |
| Clipping | Optional (`clipContent`) | Always |

### Widgets that barely change

These keep the same call syntax inside `ui:` and still use the old drawing code:

```nim
button "Save":
  save()
checkBox "Cumulative", cumulative
radioButton "Avg", option, 1
dropDown element, ["Fire", "Water", "Earth", "Air"]
progressBar progress, 0, 100
scrubber "howMuch", howMuch, 0.0, 100.0, ""
icon "heart"
textInput "input", inputText
```

`subWindow` is unchanged too:

```nim
subWindow("A SubWindow", showWindow, vec2(100, 100), vec2(400, 700)):
  text "hello":
    characters "Hello world!"
```

### Absolute placement

```nim
# Old
sk.at = vec2(100, 100)
text("Click anywhere to show the window")

# New
text "closed message":
  box 100, 100, 360, 32
  characters "Click anywhere to show the window"
```

`box` is parent-relative (`sk.pos + box`). Absolute screen coords only match when the parent origin is the screen origin.

## Custom controls

For looks that are not a stock widget, use `rectangle` plus interaction hooks. See `examples/calculator/calculator.nim` and `examples/gameplayer/gameplayer.nim`.

```nim
rectangle "ok":
  box 80, 32
  patch "button.9patch", 6
  onHover:
    tint sk.theme.buttonHoverColor
  onClick:
    doThing()
  text "ok label":
    characters "OK"
```

- `onHover` — hovered, pressed, held, or released
- `onDown` — pressed or held
- `onClick` — released inside the node
- `onClickOutside` — released outside the node

## Ids and state

Every DSL node needs a string id. Frame scroll, scrubbers, text boxes, and subwindows key state by id or title.

Use stable literal ids for anything that keeps state across frames:

```nim
# Good
textInput "name", name
scrubber "volume", volume, 0.0, 1.0
frame "itemList":
  box 200, 300

# Bad for hot paths: allocates a new id string every frame
text "time line " & $i:
  characters "..."
```

`examples/basicwindow/basicwindow_zero.nim` shows a UI that stays at zero steady-state allocs by using only literals and fixed id tables.

## Porting checklist

1. Keep `sk.beginUI` / `sk.endUi`.
2. Wrap authored UI in `ui:`.
3. Replace `text("...")` with `text "id": characters "..."`.
4. Replace `group(vec2(...), dir):` with `group "id": box ...; layout dir`.
5. Replace `sk.at = ...` with explicit `box` on `text` / `group` / `rectangle`.
6. Leave `button`, `dropDown`, `checkBox`, `textInput`, `subWindow` call sites as-is.
7. Give stateful nodes stable string-literal ids.
8. For custom chrome, follow calculator / gameplayer (`rectangle` + `patch` + `onClick`).

## Minimal side by side

```nim
# Old
sk.beginUI(window, window.size)
text("Hello")
button("Go"):
  doThing()
sk.endUi()

# New
sk.beginUI(window, window.size)
ui:
  text "greeting":
    characters "Hello"
  button "Go":
    doThing()
sk.endUi()
```

## Examples

| Example | Notes |
|---|---|
| `examples/basicwindow/basicwindow.nim` | Full widget tour |
| `examples/basicwindow/basicwindow_zero.nim` | Same UI, zero-alloc ids |
| `examples/calculator/calculator.nim` | Custom buttons with `rectangle` |
| `examples/gameplayer/gameplayer.nim` | Panels and ribbons |
| `examples/layouts/layouts.nim` | Overlap + foldouts |

Manual tests under `tests/manual_*.nim` also use the DSL.
