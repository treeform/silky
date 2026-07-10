# TodoMVC in Silky

[TodoMVC](https://todomvc.com/) is the standard small app people rebuild to compare UI frameworks. Same behavior every time: add, edit, complete, filter, clear, and persist. That makes syntax and structure easy to compare side by side.

It also matters outside demos. Browser engines use TodoMVC-style apps in Speedometer. Teams use it for onboarding and framework docs. It is small enough to read in one sitting, but large enough to exercise lists, editing, filters, and persistence.

This example is Silky's take on the [TodoMVC app spec](https://github.com/tastejs/todomvc/blob/master/app-spec.md), written with the Fidget-style DSL.

## What it covers

- Add a todo from the top input (Enter)
- Toggle one todo or mark all complete
- Double-click a title to edit (Enter saves, Escape cancels, empty deletes)
- Filter All / Active / Completed
- Clear completed
- Persist to `todos-silky.json` (native stand-in for localStorage)

## Run

```sh
cd examples/todomvc
nim r todomvc.nim
```

## Tests

```sh
cd examples/todomvc
nim r -d:silkyTesting tests/test.nim
```
