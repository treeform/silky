## Runs an offscreen Metal regression with Silky's Shady-generated shaders.
## Run on a Mac with Xcode and a Metal device:
## nim r tests/test_metal_shader_pixels.nim

when defined(macosx) and not defined(ios):
  import std/[os, osproc, tempfiles]
  import shady, silky/drawers/shader

  const
    VertexSource = toMSL(silkyVert, shaderVertex)
    FragmentSource = toMSL(silkyFrag, shaderFragment)
    HelperSource = currentSourcePath().parentDir / "metal_shader_pixels.m"

  let directory = createTempDir("silky-metal-pixels-", "")
  try:
    writeFile(directory / "vertex.metal", VertexSource)
    writeFile(directory / "fragment.metal", FragmentSource)
    let
      executable = directory / "metal_shader_pixels"
      compilation = execCmdEx(
        "xcrun --sdk macosx clang -fobjc-arc -framework Foundation " &
        "-framework Metal " & quoteShell(HelperSource) &
        " -o " & quoteShell(executable)
      )
    doAssert compilation.exitCode == 0, compilation.output
    let rendering = execCmdEx(
      quoteShell(executable) & " " & quoteShell(directory)
    )
    doAssert rendering.exitCode == 0, rendering.output
    stdout.write(rendering.output)
  finally:
    removeDir(directory)
else:
  echo "Skipped offscreen Metal pixels: requires macOS with a Metal device."
