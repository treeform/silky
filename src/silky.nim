import std/[tables]

when defined(silkyTesting):
  import silky/[semantic, atlas, widgets, textboxes, testing, common]
  export semantic, atlas, widgets, tables, textboxes, testing, common
else:
  import opengl, windy
  import silky/[drawing, atlas, widgets, textboxes, common]
  export opengl, windy, drawing, atlas, widgets, tables, textboxes, common
