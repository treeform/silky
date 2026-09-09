import
  std/unicode,
  windy

type BrowserInputs* = ref object
  windowPointer: pointer
  modifiers*: int32

{.emit: """
#include <emscripten.h>
EM_JS(void, silkyBrowserInit, (void *context), {
""" & staticRead("browsers.js") & """
  installSilkyBrowserInputs(
    document.querySelector('#canvas'),
    (rune) => _silkyBrowserRune(context, rune),
    (modifiers) => _silkyBrowserModifiers(context, modifiers)
  );
});
""".}

proc silkyBrowserRune(context: pointer, value: int32): cint
    {.exportc, cdecl, codegenDecl: "EMSCRIPTEN_KEEPALIVE $# $#$#".} =
  ## Delivers printable browser text through the normal rune callback.
  let
    inputs = cast[BrowserInputs](context)
    window = cast[Window](inputs.windowPointer)
  if window.runeInputEnabled and window.onRune != nil and
      value >= 32 and value notin 127 .. 159:
    window.onRune(Rune(value))
    return 1

proc silkyBrowserModifiers(context: pointer, modifiers: int32)
    {.exportc, cdecl, codegenDecl: "EMSCRIPTEN_KEEPALIVE $# $#$#".} =
  ## Captures DOM modifiers before Windy's keyboard callback runs.
  cast[BrowserInputs](context).modifiers = modifiers

proc silkyBrowserInit(context: pointer) {.importc, nodecl.}
  ## Installs the browser listeners for this input state.

proc newBrowserInputs*(window: Window): BrowserInputs =
  ## Bridges browser characters and modifiers to Windy's callbacks.
  result = BrowserInputs(windowPointer: cast[pointer](window))
  silkyBrowserInit(cast[pointer](result))
