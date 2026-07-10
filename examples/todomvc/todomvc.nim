## TodoMVC in Silky.
## Spec: https://github.com/tastejs/todomvc/blob/master/app-spec.md

import
  std/[os, strformat, strutils, times],
  bumpy, vmath, chroma, jsony,
  silky

type
  TodoFilter* = enum
    AllTodos
    ActiveTodos
    CompletedTodos

  Todo* = object
    id*: int
    title*: string
    completed*: bool

const
  BackgroundColor = parseHtmlColor("#000000").rgbx
  PersistPath = "todos-silky.json"
  DoubleClickTime = 0.4

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "H1", 32.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 18.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "TodoMVC",
  ivec2(560, 720),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "dist/atlas.png")

sk.theme.defaultTextColor = parseHtmlColor("#2C3E50").rgbx
sk.theme.disabledTextColor = parseHtmlColor("#95A5A6").rgbx
sk.theme.errorTextColor = parseHtmlColor("#E74C3C").rgbx
sk.theme.textColor = parseHtmlColor("#2C3E50").rgbx
sk.theme.textH1Color = parseHtmlColor("#1A252F").rgbx
sk.theme.frameFocusColor = parseHtmlColor("#D5DBDB").rgbx
sk.theme.buttonHoverColor = rgbx(200, 200, 200, 255)
sk.theme.buttonDownColor = rgbx(180, 180, 180, 255)

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

var
  showWindow = true
  todos: seq[Todo]
  nextId = 1
  newTitle = ""
  filter = AllTodos
  editingId = -1
  editTitle = ""
  lastClickId = -1
  lastClickTime = 0.0
  dirty = false

proc activeCount(): int =
  ## Counts todos that are not completed.
  for todo in todos:
    if not todo.completed:
      inc result

proc completedCount(): int =
  ## Counts completed todos.
  for todo in todos:
    if todo.completed:
      inc result

proc visible(todo: Todo): bool =
  ## Returns true when the todo matches the active filter.
  case filter
  of AllTodos:
    true
  of ActiveTodos:
    not todo.completed
  of CompletedTodos:
    todo.completed

proc itemsLeftLabel(): string =
  ## Pluralized active-item counter text.
  let n = activeCount()
  if n == 1:
    "1 item left"
  else:
    $n & " items left"

proc saveTodos() =
  ## Writes todos to disk in TodoMVC-style JSON.
  writeFile(PersistPath, todos.toJson())
  dirty = false

proc loadTodos() =
  ## Loads todos from disk if the persist file exists.
  if not fileExists(PersistPath):
    return
  try:
    todos = readFile(PersistPath).fromJson(seq[Todo])
  except CatchableError:
    todos = @[]
  nextId = 1
  for todo in todos:
    if todo.id >= nextId:
      nextId = todo.id + 1

proc addTodo(title: string) =
  ## Adds a trimmed non-empty todo and marks state dirty.
  let trimmed = title.strip()
  if trimmed.len == 0:
    return
  todos.add(Todo(id: nextId, title: trimmed, completed: false))
  inc nextId
  dirty = true

proc removeTodo(id: int) =
  ## Removes a todo by id.
  for i in countdown(todos.len - 1, 0):
    if todos[i].id == id:
      todos.delete(i)
      dirty = true
      break
  if editingId == id:
    editingId = -1
    editTitle = ""

proc clearCompleted() =
  ## Removes all completed todos.
  var kept: seq[Todo]
  for todo in todos:
    if not todo.completed:
      kept.add(todo)
  todos = kept
  dirty = true

proc toggleAll(completed: bool) =
  ## Sets every todo to the given completed state.
  for i in 0 ..< todos.len:
    todos[i].completed = completed
  dirty = true

proc beginEdit(id: int, title: string) =
  ## Enters editing mode for one todo.
  editingId = id
  editTitle = title
  if "edit" in textBoxStates:
    textBoxStates["edit"].focused = true

proc commitEdit() =
  ## Saves or destroys the todo being edited.
  if editingId < 0:
    return
  let trimmed = editTitle.strip()
  if trimmed.len == 0:
    removeTodo(editingId)
  else:
    for i in 0 ..< todos.len:
      if todos[i].id == editingId:
        todos[i].title = trimmed
        dirty = true
        break
  editingId = -1
  editTitle = ""

proc cancelEdit() =
  ## Leaves editing mode without saving.
  editingId = -1
  editTitle = ""

proc handleTodoClick(id: int, title: string) =
  ## Single click selects; double click starts editing.
  let now = epochTime()
  if id == lastClickId and now - lastClickTime < DoubleClickTime:
    beginEdit(id, title)
    lastClickId = -1
  else:
    lastClickId = id
    lastClickTime = now

loadTodos()

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)
  var removeId = -1

  for x in 0 ..< 16:
    for y in 0 ..< 10:
      sk.drawImage(
        "testTexture",
        vec2(x.float32 * 256, y.float32 * 256),
        rgbx(30, 30, 30, 255)
      )

  # Commit new todos on Enter while the new-item field is focused.
  if "new" in textBoxStates and textBoxStates["new"].focused and
      window.buttonPressed[KeyEnter]:
    addTodo(newTitle)
    newTitle = ""
    if "new" in textBoxStates:
      textBoxStates["new"].setText("")

  # Editing shortcuts.
  if editingId >= 0:
    if window.buttonPressed[KeyEnter]:
      commitEdit()
    elif window.buttonPressed[KeyEscape]:
      cancelEdit()

  if dirty:
    saveTodos()

  ui:
    subWindow("todos", showWindow, vec2(40, 40), vec2(460, 620)):
      text "heading":
        characters "todos"
        font "H1"
        tint sk.theme.textH1Color

      textInput "new", newTitle

      if todos.len > 0:
        var markAll = activeCount() == 0
        let markAllBefore = markAll
        group "mark all row":
          box 400, 32
          layout LeftToRight
          itemSpacing 8
          checkBox "Mark all as complete", markAll
        if markAll != markAllBefore:
          toggleAll(markAll)

        group "filters":
          box 400, 34
          layout LeftToRight
          itemSpacing 8
          button "All", filter != AllTodos:
            filter = AllTodos
          button "Active", filter != ActiveTodos:
            filter = ActiveTodos
          button "Completed", filter != CompletedTodos:
            filter = CompletedTodos

        text "count":
          characters itemsLeftLabel()

        if completedCount() > 0:
          button "Clear completed":
            clearCompleted()

        frame "list":
          box 420, 360
          layout TopToBottom
          itemSpacing 6
          for todo in todos:
            if not todo.visible:
              continue
            let
              todoId = todo.id
              todoTitle = todo.title
            if editingId == todoId:
              group "edit row:" & $todoId:
                box 400, 36
                textInput "edit", editTitle
            else:
              group "row:" & $todoId:
                box 400, 36
                layout LeftToRight
                itemSpacing 8
                var done = todo.completed
                let doneBefore = done
                checkBox "", done
                if done != doneBefore:
                  for i in 0 ..< todos.len:
                    if todos[i].id == todoId:
                      todos[i].completed = done
                      dirty = true
                      break
                rectangle "title:" & $todoId:
                  box 280, 32
                  onClick:
                    handleTodoClick(todoId, todoTitle)
                  text "title text:" & $todoId:
                    box 0, 6, 280, 22
                    characters todoTitle
                    if todo.completed:
                      tint sk.theme.disabledTextColor
                button "x":
                  removeId = todoId
          if removeId >= 0:
            removeTodo(removeId)

    if not showWindow:
      text "closed":
        box 40, 40, 300, 32
        characters "Click to show todos"
      if window.buttonPressed[MouseLeft]:
        showWindow = true

    let ms = sk.avgFrameTime * 1000
    text "frame time":
      box sk.size.x - 250, 20, 230, 22
      characters &"frame time: {ms:>7.3f}ms"

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
