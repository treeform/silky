## Menu System UI tests using semantic capture.
## Run with: nim r tests/test.nim (from menu folder)

when not defined(silkyTesting):
  {.error: "Must compile with -d:silkyTesting".}

import
  std/[unittest],
  silky,
  ../menu {.all.}

suite "Menu UI - Initial State":

  setup:
    window.pumpFrame(sk)

  test "menu state is ready after a frame":
    check menuState != nil
    check menuState.openPath.len == 0

  test "multiple frames keep menus closed by default":
    window.pumpFrame(sk)
    check menuState.openPath.len == 0
    window.pumpFrame(sk)
    check menuState.openPath.len == 0
