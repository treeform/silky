import std/[tables]

when defined(silkyTesting):
  import silky/[semantic, atlas, widgets, textboxes, testing]
  export semantic, atlas, widgets, tables, textboxes, testing
else:
  import windy
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4) and
      not defined(useCpu):
    import opengl
  import silky/[contexts, atlas, widgets, textboxes]
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4) and
      not defined(useCpu):
    export opengl
  export windy, contexts, atlas, widgets, tables, textboxes
  when defined(useMetal4):
    proc loadExtensions*() {.inline.} =
      ## No-op helper for non-OpenGL backends.
      discard
