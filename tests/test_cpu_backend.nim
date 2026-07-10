when defined(useCpu) and defined(windows):
  import
    chroma, vmath,
    silky

  let
    builder = newAtlasBuilder(64, 2)
    window = newWindow(
      "Silky CPU backend smoke test",
      ivec2(64, 64),
      visible = false,
      vsync = false
    )
  makeContextCurrent(window)
  loadExtensions()

  let sk = newSilky(window, builder.atlasImage, builder.atlas)
  sk.beginUi(window, window.size)
  sk.clearScreen(rgbx(10, 20, 30, 255))
  sk.drawRect(vec2(8, 8), vec2(24, 24), rgbx(255, 0, 0, 255))
  sk.endUi()
  window.swapBuffers()
  window.close()

  echo "Silky CPU backend smoke test passed"
else:
  echo "Silky CPU backend smoke test skipped"
