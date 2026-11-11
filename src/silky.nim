import std/[tables]
from silky/common import SilkyError
export SilkyError

when defined(silkyTesting):
  import silky/[
    semantics, atlas, widgets, textboxes, richtextboxes, testing, dsl, menus,
    profiles
  ]
  export semantics except textInputs
  export atlas, tables, textboxes, richtextboxes, testing, dsl, menus, profiles
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
  import silky/[contexts, atlas, widgets, textboxes, richtextboxes, dsl, menus]
  when not defined(useDirectX) and
      not defined(useVulkan) and
      not defined(useMetal4) and
      not defined(useCpu):
    export opengl
  export contexts except textInputs
  export windy, atlas, tables, textboxes, richtextboxes, dsl, menus
  export widgets except
    button, checkBox, clickableIcon, dropDown, frame, group, h1text, icon,
    iconButton, image, listBox, progressBar, radioButton, ribbon, scrubber, text
