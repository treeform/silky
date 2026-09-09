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

Emscripten builds automatically capture modifiers from DOM keyboard events.
When Windy cancels a printable keydown and prevents its keypress, Silky delivers
the browser's character through the rune callback. Shortcut keys do not insert
characters, and a corresponding keypress cannot insert the character twice.
This requires no application setup and does not add IME composition support.

Run `nim r tests/manual_inputs.nim` from the repository root to try single-line,
password, and multiline fields with a keyboard display. Hold keys outside the
fields to highlight them, then click a field and type to check suppression.
