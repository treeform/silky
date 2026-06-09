## Compiles all examples first, then runs them sequentially.

import std/[osproc, os, strformat]

const Examples = [
  "basicwindow",
  "calculator",
  "gameplayer",
  "layouts",
  "menu",
  "panels",
  "the7gui",
]

const BuildFlags =
  when defined(useDirectX):
    "-d:useDirectX"
  elif defined(useVulkan):
    "-d:useVulkan"
  elif defined(useMetal4):
    "-d:useMetal4"
  elif defined(useCpu):
    "-d:useCpu"
  else:
    ""

proc main() =
  ## Compile all examples, then run all examples in sequence.
  let
    startDir = getCurrentDir()
    rootDir = currentSourcePath().parentDir.parentDir
    examplesDir = rootDir / "examples"
  defer:
    setCurrentDir(startDir)

  echo "=== Silky Examples Runner ==="
  echo "Compiling all examples first."
  echo "Running all examples after successful compilation."
  echo "Close each window to proceed to the next example.\n"

  for i, name in Examples:
    let
      exampleDir = examplesDir / name
      nimFile = name & ".nim"

    echo fmt"[{i + 1}/{Examples.len}] Compiling: {name}"

    # Change to example directory so the compiler can resolve local files.
    setCurrentDir(exampleDir)

    let compileCmd =
      if BuildFlags.len == 0:
        fmt"nim c {nimFile}"
      else:
        fmt"nim c {BuildFlags} {nimFile}"
    let exitCode = execCmd(compileCmd)
    if exitCode != 0:
      echo fmt"  ERROR: {name} failed to compile with exit code {exitCode}"
      quit(exitCode)
    echo ""

  echo "=== Compilation complete ===\n"

  for i, name in Examples:
    let
      exampleDir = examplesDir / name
      binaryPath = "." / name

    echo fmt"[{i + 1}/{Examples.len}] Running: {name}"

    # Change to example directory so each app can find its data folder.
    setCurrentDir(exampleDir)

    let exitCode = execCmd(binaryPath)
    if exitCode != 0:
      echo fmt"  ERROR: {name} failed with exit code {exitCode}"
      quit(exitCode)
    echo ""

  echo "=== All examples completed ==="

when isMainModule:
  main()
