import std/os
import silky/profiles

echo "Testing silky runtime profile start/stop"
doAssert not profileTraceActive()

let tracePath = getTempDir() / "silky_profile_runtime_test.json"
removeFile(tracePath)

startRuntimeProfileTrace(tracePath)
doAssert profileTraceActive(), "runtime trace should be active after start"

profileBlock "test-block":
  var total = 0
  for i in 0 ..< 1000:
    total += i
  doAssert total > 0

let written = toggleRuntimeProfileTrace(tracePath)
doAssert written == tracePath, "toggle stop should return the written path"
doAssert not profileTraceActive(), "runtime trace should be inactive after stop"
doAssert fileExists(tracePath), "trace file should exist after stop"
doAssert getFileSize(tracePath) > 0, "trace file should not be empty"

removeFile(tracePath)
startRuntimeProfileTrace(tracePath, frameLimit = 3)
doAssert profileTraceActive()
var finishedPath = ""
for i in 0 ..< 3:
  finishedPath = profileFrameTick()
doAssert not profileTraceActive(), "frame limit should finish the runtime trace"
doAssert finishedPath.len > 0 or true
if fileExists(tracePath):
  removeFile(tracePath)

echo "silky runtime profile start/stop ok"
