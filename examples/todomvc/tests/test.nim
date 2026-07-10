## TodoMVC UI tests using semantic capture.
## Run with: nim r -d:silkyTesting tests/test.nim

when not defined(silkyTesting):
  {.error: "Must compile with -d:silkyTesting".}

import
  std/[os, unittest],
  silky,
  ../todomvc {.all.}

proc resetState() =
  ## Clears todos and UI state for a clean test.
  todos.setLen(0)
  nextId = 1
  newTitle = ""
  filter = AllTodos
  editingId = -1
  editTitle = ""
  lastClickId = -1
  lastClickTime = 0.0
  dirty = false
  showWindow = true
  if fileExists(PersistPath):
    removeFile(PersistPath)

suite "TodoMVC - Initial State":
  setup:
    resetState()
    window.pumpFrame(sk)

  test "window and heading present":
    check sk.semantic.root.findByName("todos", "SubWindow") != nil
    check sk.semantic.root.findByText("todos", "Text") != nil

  test "main and footer hidden when empty":
    check sk.semantic.root.findByText("Mark all as complete") == nil
    check sk.semantic.root.findByText("Clear completed") == nil
    check sk.semantic.root.findByText("0 items left") == nil

suite "TodoMVC - Add and Complete":
  setup:
    resetState()

  test "adding a todo shows it and the footer":
    addTodo("Buy milk")
    window.pumpFrame(sk)
    check sk.semantic.root.findByText("Buy milk") != nil
    check sk.semantic.root.findByText("1 item left") != nil
    check sk.semantic.root.findByText("Mark all as complete") != nil

  test "toggle complete updates counter":
    addTodo("Walk dog")
    window.pumpFrame(sk)
    todos[0].completed = true
    dirty = true
    window.pumpFrame(sk)
    check sk.semantic.root.findByText("0 items left") != nil
    check sk.semantic.root.findByText("Clear completed") != nil

  test "clear completed removes done todos":
    addTodo("Keep")
    addTodo("Drop")
    todos[1].completed = true
    clearCompleted()
    window.pumpFrame(sk)
    check todos.len == 1
    check todos[0].title == "Keep"
    check sk.semantic.root.findByText("Drop") == nil

  test "delete button removes todo after list render":
    addTodo("Drop")
    window.pumpFrame(sk)
    window.clickButton(sk, "x")
    window.pumpFrame(sk)
    check todos.len == 0
    check sk.semantic.root.findByText("Drop") == nil

suite "TodoMVC - Filters":
  setup:
    resetState()
    addTodo("Active one")
    addTodo("Done one")
    todos[1].completed = true

  test "active filter hides completed":
    filter = ActiveTodos
    window.pumpFrame(sk)
    check sk.semantic.root.findByText("Active one") != nil
    check sk.semantic.root.findByText("Done one") == nil

  test "completed filter hides active":
    filter = CompletedTodos
    window.pumpFrame(sk)
    check sk.semantic.root.findByText("Active one") == nil
    check sk.semantic.root.findByText("Done one") != nil

suite "TodoMVC - Persistence":
  setup:
    resetState()

  test "save and load round trip":
    addTodo("Persist me")
    saveTodos()
    check fileExists(PersistPath)
    todos.setLen(0)
    loadTodos()
    check todos.len == 1
    check todos[0].title == "Persist me"
