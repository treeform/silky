import std/[tables]

when defined(silkyTesting):
  import silky/[semantic, atlas, widgets, textboxes, testing, common, scrollbars, layout]
  export semantic, atlas, widgets, tables, textboxes, testing, common, scrollbars, layout
else:
  import opengl, windy
  import silky/[drawing, atlas, widgets, textboxes, common, scrollbars, layout]
  export opengl, windy, drawing, atlas, widgets, tables, textboxes, common, scrollbars, layout
