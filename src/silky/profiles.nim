const
  ProfileTracePath* {.strdefine.} = ""
  ProfileNumFrames* {.intdefine.} = 100

when ProfileTracePath.len > 0:
  import
    std/os,
    fluffy/measure

  export measure

  var
    profileStarted = false
    profileDumped = false
    profileFrameCount = 0

  proc ensureProfileDir() =
    ## Creates the parent directory for the profile trace.
    let dir = ProfileTracePath.parentDir()
    if dir.len > 0:
      createDir(dir)

  proc startProfileTrace*() =
    ## Starts the Fluffy trace capture once.
    if profileStarted:
      return
    profileStarted = true
    ensureProfileDir()
    echo "Profile trace enabled: ", ProfileTracePath
    echo "Profile frames: ", ProfileNumFrames
    startTrace()

  proc finishProfileTrace*() =
    ## Stops and writes the Fluffy trace capture once.
    if not profileStarted or profileDumped:
      return
    profileDumped = true
    endTrace()
    ensureProfileDir()
    dumpMeasures(ProfileTracePath)
    echo "Profile trace written: ", ProfileTracePath

  proc profileShouldDump*(): bool =
    ## Returns true when the profile frame budget has elapsed.
    ProfileNumFrames > 0 and
      profileFrameCount >= ProfileNumFrames and
      not profileDumped

  proc beginProfileFrame*() =
    ## Starts profiling on the first measured UI frame.
    if not profileStarted:
      startProfileTrace()

  proc endProfileFrame*() =
    ## Counts one UI frame and dumps/exits when the budget elapses.
    if not profileStarted or profileDumped:
      return
    inc profileFrameCount
    if profileShouldDump():
      finishProfileTrace()
      quit(0)

  template profileBlock*(name: string, body: untyped) =
    ## Measures a named block while profiling is enabled.
    measurePush(name)
    body
    measurePop()
else:
  macro measure*(fn: untyped): untyped =
    ## Leaves a measured procedure unchanged when profiling is disabled.
    fn

  template measurePush*(what: string) =
    ## No-op profile begin marker.
    discard

  template measurePop*() =
    ## No-op profile end marker.
    discard

  proc startProfileTrace*() =
    ## Leaves profiling disabled.
    discard

  proc finishProfileTrace*() =
    ## Leaves profiling disabled.
    discard

  proc profileShouldDump*(): bool =
    ## Returns false when profiling is disabled.
    false

  proc beginProfileFrame*() =
    ## Leaves profiling disabled.
    discard

  proc endProfileFrame*() =
    ## Leaves profiling disabled.
    discard

  template profileBlock*(name: string, body: untyped) =
    ## Runs a block without profiling.
    body
