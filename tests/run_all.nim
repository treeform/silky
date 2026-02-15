## Compiles and runs all examples sequentially for visual verification.

import std/[osproc, os, strformat]

const Examples = [
  "basicwindow",
  "calculator",
  "gameplayer",
  "menu",
  "panels",
  "the7gui",
]

proc main() =
  ## Run all examples in sequence.
  let
    rootDir = currentSourcePath().parentDir.parentDir
    examplesDir = rootDir / "examples"

  echo "=== Silky Examples Runner ==="
  echo "Compiling and running each example."
  echo "Close each window to proceed to the next example.\n"

  for i, name in Examples:
    let
      exampleDir = examplesDir / name
      nimFile = name & ".nim"

    echo fmt"[{i + 1}/{Examples.len}] Compiling and running: {name}"

    # Change to example directory so it can find its data folder
    setCurrentDir(exampleDir)

    let exitCode = execCmd(fmt"nim r {nimFile}")
    if exitCode != 0:
      echo fmt"  ERROR: {name} failed with exit code {exitCode}"
      quit(exitCode)
    echo ""

  echo "=== All examples completed ==="

when isMainModule:
  main()
