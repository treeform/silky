import std/[tables]

when defined(silkyTesting):
  import silky/[semantics, atlas, widgets, textboxes, testing, dsl, menus, profiles]
  export semantics, atlas, tables, textboxes, testing, dsl, menus, profiles
  export widgets except
    button, checkBox, clickableIcon, dropDown, frame, group, h1text, icon,
    iconButton, image, listBox, progressBar, radioButton, ribbon, scrubber, text
else:
  import windy
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4) and
      not defined(useCpu):
    import opengl
  import silky/[contexts, atlas, widgets, textboxes, dsl, menus, profiles]
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4) and
      not defined(useCpu):
    export opengl
  export windy, contexts, atlas, tables, textboxes, dsl, menus, profiles
  export widgets except
    button, checkBox, clickableIcon, dropDown, frame, group, h1text, icon,
    iconButton, image, listBox, progressBar, radioButton, ribbon, scrubber, text

  when defined(useMetal4) or defined(useCpu):
    proc loadExtensions*() {.inline.} =
      ## No-op helper for non-OpenGL backends.
      discard
