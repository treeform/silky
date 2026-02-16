import std/[tables]

when defined(silkyTesting):
  import silky/[semantic, atlas, widgets, textboxes, testing, common, scrollbars]
  export semantic, atlas, widgets, tables, textboxes, testing, common, scrollbars
else:
  import opengl, windy
  import silky/[drawing, atlas, widgets, textboxes, common, scrollbars]
  export opengl, windy, drawing, atlas, widgets, tables, textboxes, common, scrollbars
