## Layout window UI tests using semantic capture.
## Run with: nim r tests/test.nim (from layouts folder)

when not defined(silkyTesting):
  {.error: "Must compile with -d:silkyTesting".}

import
  unittest,
  vmath, bumpy, silky,
  ../layouts {.all.}

proc resetState() =
  ## Resets the layout example state.
  showOverlapWindow = true

suite "Layouts - Overlap Test":
  setup:
    resetState()
    window.pumpFrame(sk)

  test "buttons overlap - rects intersect":
    let
      behind = sk.semantic.root.findByName("behind", "Rectangle")
      inFront = sk.semantic.root.findByName("front", "Rectangle")
    check inFront.rect.x < behind.rect.x + behind.rect.w
    check inFront.rect.x + inFront.rect.w > behind.rect.x
    check inFront.rect.y < behind.rect.y + behind.rect.h
    check inFront.rect.y + inFront.rect.h > behind.rect.y

  test "In Front button is rendered after Behind":
    let
      behind = sk.semantic.root.findByName("behind", "Rectangle")
      inFront = sk.semantic.root.findByName("front", "Rectangle")
    check inFront.childIndex > behind.childIndex

  test "clicking in the overlapped zone triggers only In Front":
    let
      behind = sk.semantic.root.findByName("behind", "Rectangle")
      inFront = sk.semantic.root.findByName("front", "Rectangle")
      intersection = behind.rect and inFront.rect
      overlapCenter = intersection.xy + intersection.wh * 0.5'f

    window.pumpFrame(sk)
    window.moveMouse(overlapCenter.x.int, overlapCenter.y.int)
    window.pressButton(MouseLeft)
    window.pumpFrame(sk)
    window.releaseButton(MouseLeft)
    window.pumpFrame(sk)

    check behindClicked == false
    check inFrontClicked == true
