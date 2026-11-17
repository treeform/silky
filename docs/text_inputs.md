# Text input

Construct Silky normally with `newSilky`. Text boxes activate text input when
clicked and keep it active between frames while focused. Clicking away, omitting
the focused field from a frame, or changing window focus ends text input. A
disabled field can select and copy text but cannot edit it.

Use `sk.buttonDown`, `sk.buttonPressed`, and `sk.buttonReleased` for application
controls. Keyboard keys in these views are false during text input, so typing
WASD cannot also move a character. Mouse buttons continue to work. Windy's raw
`window.buttonDown`, `window.buttonPressed`, and `window.buttonReleased` remain
unfiltered.

Creating Silky from a window automatically installs its input handlers. No
callback registration or input setup is needed. If window callbacks change,
Silky refreshes its handlers at the start of the next UI frame.

Application keyboard and rune callbacks are consumed during text input. Mouse
and focus callbacks still run. On entering text input, previously forwarded key
holds receive release callbacks so application controls do not remain stuck.
The corresponding physical releases are then consumed once.

Remove any manual `inputRunes` forwarding and `runeInputEnabled` assignments.
Silky manages rune input automatically. Each focused text box processes all
pending text edits in arrival order before drawing, using modifiers captured
with each event. There is no setup call or public queue to manage. Input beyond
the internal limit of 65,536 pending events raises `SilkyError`.

Native and Emscripten builds use the same Windy callbacks for text and modifier
state. No browser-specific input setup is needed.

Run `nim r tests/manual_inputs.nim` from the repository root to try single-line,
password, and multiline fields with a keyboard display. Hold keys outside the
fields to highlight them, then click a field and type to check suppression.

## Navigating rich text inside a scrolling frame

A rich text box scrolls its own content when the cursor moves. If the box is
sized to the full document height, the enclosing frame owns scrolling instead.
After drawing the box, `state.cursorNavigated` reports whether it consumed an
arrow, Home, End, Page Up, or Page Down press. This includes repeated presses and
Shift selections, even when the cursor is already at a document boundary.
The flag resets on each widget draw. Clicking, copying, Select All, and streamed
text changes do not set it.

Use `revealScroll` to calculate the enclosing frame's scroll position. It accepts
the scroll used to place the target, the complete content size, and the viewport
and target rectangles in the same window coordinates. It supports all four
stack directions and clamps to the content bounds. Its optional margin defaults
to four layout units. Apply the result after the frame finishes laying out and
processing its scrollbars.

```nim
# Save this before drawing the enclosing frame.
let previousScroll = frameStates["history"].scrollPos
var
  revealCursor = false
  caret: Rect

# Inside the frame, after placing the full-height reply.
let textOrigin = sk.at + vec2(sk.theme.padding.float32)
sk.richTextBox(window, "reply", text, replyWidth, replyHeight)
let state = richTextBoxStates["reply"]
if state.cursorNavigated:
  let local = state.editor.locationRect(state.editor.cursor)
  caret = rect(textOrigin + local.xy - state.editor.scrollPos, local.wh)
  revealCursor = true

# After the frame or UI finishes drawing.
if revealCursor:
  frameStates["history"].scrollPos = revealScroll(
    previousScroll,
    contentSize,
    viewport,
    caret,
    BottomToTop
  )
```

Apply this only while the window is focused and no modal control owns input.
When using on-demand rendering, request another frame if the scroll changed.
Apps that skip invisible messages must still draw the focused rich text widget
so it can consume navigation keys. Do not call `revealScroll` unconditionally
each frame, or ordinary wheel scrolling will keep returning to the cursor.
