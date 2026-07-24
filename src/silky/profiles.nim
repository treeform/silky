## Fluffy profile helpers for Silky.
##
## Compile-time static capture (existing):
##   nim r -d:ProfileTracePath=tmp/perf.json -d:ProfileNumFrames=100 ...
##
## Runtime start/stop (for games and interactive tools):
##   startRuntimeProfileTrace("tmp/perf.json")
##   finishProfileTrace()
##   toggleRuntimeProfileTrace("tmp/perf.json")

import
  std/os,
  fluffy/measure

export measure

const
  ProfileTracePath* {.strdefine.} = ""
  ProfileNumFrames* {.intdefine.} = 100
  DefaultRuntimeProfileTracePath* = "perf.json"

var
  profileStarted = false
  profileDumped = false
  profileQuitAfter = false
  profileTracePath = ""
  profileFrameLimit = 0
  profileFrameCount = 0

proc profileTraceActive*(): bool =
  ## Returns true while a profile trace is actively recording.
  profileStarted and not profileDumped

proc ensureProfileDir(path: string) =
  ## Creates the parent directory for the profile trace.
  let dir = path.parentDir()
  if dir.len > 0:
    createDir(dir)

proc startProfileTraceAt(
  path: string,
  frameLimit = 0,
  quitAfter = false
) =
  ## Starts one Fluffy capture at a concrete path.
  if profileStarted:
    return
  if path.len == 0:
    echo "Profile trace path is empty"
    return
  profileStarted = true
  profileDumped = false
  profileQuitAfter = quitAfter
  profileTracePath = path
  profileFrameLimit = max(0, frameLimit)
  profileFrameCount = 0
  ensureProfileDir(path)
  echo "Profile trace enabled: ", profileTracePath
  if profileFrameLimit > 0:
    echo "Profile frames: ", profileFrameLimit
  startTrace()

proc startProfileTrace*() =
  ## Starts a compile-time configured static capture when ProfileTracePath is set.
  when ProfileTracePath.len > 0:
    startProfileTraceAt(
      ProfileTracePath,
      frameLimit = ProfileNumFrames,
      quitAfter = true
    )

proc startRuntimeProfileTrace*(
  path = DefaultRuntimeProfileTracePath,
  frameLimit = 0,
  quitAfter = false
) =
  ## Starts a Fluffy capture at runtime without requiring ProfileTracePath.
  let tracePath =
    if path.len > 0:
      path
    else:
      DefaultRuntimeProfileTracePath
  startProfileTraceAt(
    tracePath,
    frameLimit = frameLimit,
    quitAfter = quitAfter
  )

proc finishProfileTrace*(): string =
  ## Stops and writes the active trace. Returns the written path, or "".
  if not profileStarted or profileDumped:
    return ""
  let
    path = profileTracePath
    shouldQuit = profileQuitAfter
  profileDumped = true
  endTrace()
  ensureProfileDir(path)
  try:
    dumpMeasures(path)
  except Exception as error:
    echo "Profile trace dump failed: ", error.msg
  profileStarted = false
  profileQuitAfter = false
  profileFrameLimit = 0
  profileFrameCount = 0
  profileTracePath = ""
  if fileExists(path):
    echo "Profile trace written: ", path
    result = path
  if shouldQuit:
    quit(0)

proc toggleRuntimeProfileTrace*(
  path = DefaultRuntimeProfileTracePath
): string =
  ## Toggles runtime capture. Returns the written path when stopping, else "".
  if profileTraceActive():
    result = finishProfileTrace()
  else:
    startRuntimeProfileTrace(path)
    result = ""

proc profileShouldDump*(): bool =
  ## Returns true when the profile frame budget has elapsed.
  profileFrameLimit > 0 and
    profileFrameCount >= profileFrameLimit and
    profileTraceActive()

proc beginProfileFrame*() =
  ## Auto-starts a compile-time static capture on the first measured UI frame.
  when ProfileTracePath.len > 0:
    if not profileStarted:
      startProfileTrace()

proc endProfileFrame*() =
  ## Counts one UI frame and finishes when a frame budget elapses.
  if not profileTraceActive():
    return
  inc profileFrameCount
  if profileShouldDump():
    discard finishProfileTrace()

proc profileFrameTick*(): string =
  ## Advances one rendered frame for runtime captures without quitting.
  ## Returns the written path when this tick finishes a bounded capture.
  result = ""
  if not profileTraceActive():
    return
  inc profileFrameCount
  if profileFrameLimit > 0 and profileFrameCount >= profileFrameLimit:
    profileQuitAfter = false
    result = finishProfileTrace()

template profileBlock*(name: string, body: untyped) =
  ## Measures a named block while Fluffy tracing is enabled.
  measurePush(name)
  body
  measurePop()
