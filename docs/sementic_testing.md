## Semantic testing for Silky UI

This document explains the idea behind semantic UI testing in Silky, why it helps writing tests and AI assisted development.

## The testing problem

Normal tests and AI tools are not great at verifying GUI output when they must rely on pixels.

- Pixel based checks are slow and expensive.
- GUI automation usually needs a full window, GPU, and frame rendering loop.
- Most AI verification tools are stronger with text than with images.
- For immediate mode GUI, dumping every frame is noisy because frames update constantly.

In short: we need a fast, text first way to inspect and test UI behavior.

## Core idea ui semantic mode

Compile and run Silky apps in a semantic testing mode that captures what the UI logically renders instead of what it rasterizes.

- Capture widgets as a semantic tree (kind, name, text, state, rect, children).
- Tests can walk the tree, assert on logical state, and interact with the UI.
- Export that tree as stable text snapshots.
- Compare snapshots with golden files in tests.
- Provide query and interaction helpers for tests and AI tools.
- Emit diffs only when the semantic output changes.

This gives us browser style inspectability for native GUI, without browser overhead.

## Why this helps live coding and AI verification

- The output is nodes and text, so AI can read, reason, and compare quickly.
- No image scraping or OCR is required.
- Tests can assert logical intent: "button exists", "display text changed", "checkbox is checked".
- Iteration is faster because semantic capture avoids real rendering cost.
- Diffs are smaller than full frame dumps and are easier to review.

## Current implementation in Silky

The current implementation already provides the core semantic capture pipeline.

### Compile flag

- Tests are compiled with `-d:silkyTesting`. This gives you mock window, rendering, and frame pumping.
- Test files assert this flag to avoid accidental non testing runs.
- Tests can also use diffs for golden file testing.

### Semantic model

`src/silky/semantic.nim` defines:

- `SemanticNode` for widget kind, name, text, rect, state, parent and children.
- `SemanticCapture` for per frame tree capture, stack management, frame number, and previous snapshot support.
- Snapshot export with `toText()` and `toSnapshot()`.
- Search helpers:
  - `findByPath()`
  - `findByText()`
  - `findByName()`
  - `findAllByText()`
- Simple text diff with `diff(old, new)`.

### Frame integration

In semantic mode:

- `beginUi()` resets semantic capture each frame.
- `beginWidget()` pushes a semantic node.
- `setWidgetState()` records interactive state.
- `setWidgetRect()` updates geometry.
- `endWidget()` pops the node.
- `semanticSnapshot()` returns snapshot text for tests.

### Example app and tests

The calculator example shows end to end usage:

- `examples/calculator/calculator.nim` annotates widgets with semantic metadata, including display name and button text.
- `examples/calculator/tests/test.nim` drives the UI using semantic helpers like `clickButton`, queries nodes by text/name, and asserts display output.

## Snapshot format

The snapshot is a readable tree, for example:

```text
frame: 3
Calculator:
  type: SubWindow
  children:
    display:
      type: Display
      text: 7+3
    1:
      type: Button
      text: =
```

This is a simple tree text format, but controlled by Silky so it stays stable for testing.

## Test workflow

Recommended flow for semantic UI tests:

### Unit test

1. Build and run app/test with `-d:silkyTesting`.
2. Pump a frame and capture semantic snapshot.
3. Query nodes and assert logical state.
4. Trigger interaction, click or type text.
5. Assert on new state.

### Golden file test

1. Build and run app/test with `-d:silkyTesting`.
2. Pump a frame and capture semantic snapshot.
3. Keep doing some complex actions and diffs snapshots.
4. Compare against golden output.

This supports both direct assertions and golden master testing.

## Diff strategy

Silky currently has line by line snapshot diffing.

- If no semantic change occurs, diff is empty.
- If semantic output changes, tests can print only changed lines.
- This avoids frame by frame spam in immediate mode.

Future improvement: keep and publish diffs automatically only when changed from previous frame.

## Interaction strategy

Current tests already click controls by button text.

Next steps can add:

- Click by semantic path.
- Click by index under a container.
- Text lookup with disambiguation when duplicate labels exist.
- Script style actions (`click`, `type`, `assertText`, `expectVisible`).

## Performance expectations

Semantic mode should be much faster than full GUI automation because:

- No real drawing pipeline is needed.
- No GPU rasterization is required.
- Data is captured in memory as plain structures and text.

This makes it suitable for CI, local rapid iteration, and AI driven verification loops.

## Summary

Semantic testing gives Silky a practical path for reliable UI verification without pixel testing. It fits immediate mode UI, works well with AI tools, and is already partially implemented with semantic capture, querying, diffing, and real example coverage in calculator tests.
