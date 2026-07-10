import std/[tables]

when defined(silkyTesting):
  import silky/[semantic, atlas, widgets, textboxes, testing, fidgetdsl, menus, profiles]
  export semantic, atlas, tables, textboxes, testing, fidgetdsl, menus, profiles
  export widgets except
    button, checkBox, clickableIcon, dropDown, frame, group, h1text, icon,
    iconButton, image, listBox, progressBar, radioButton, ribbon, scrubber, text
else:
  import windy
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4):
    import opengl
  import silky/[contexts, atlas, widgets, textboxes, fidgetdsl, menus, profiles]
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4):
    export opengl
  export windy, contexts, atlas, tables, textboxes, fidgetdsl, menus, profiles
  export widgets except
    button, checkBox, clickableIcon, dropDown, frame, group, h1text, icon,
    iconButton, image, listBox, progressBar, radioButton, ribbon, scrubber, text

  when defined(useMetal4):
    proc loadExtensions*() {.inline.} =
      ## No-op helper for non-OpenGL backends.
      discard
