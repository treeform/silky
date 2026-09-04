## UI pattern gallery tests using semantic capture.

when not defined(silkyTesting):
  {.error: "Must compile with -d:silkyTesting".}

import
  std/tables,
  silky,
  ../patterns {.all.}

proc resetState() =
  ## Resets the gallery to its initial interactive state.
  category = ControlsPage
  email = "you@company.com"
  notifications = true
  contactMethod = 1
  alignment = 2
  volume = 42.0
  copies = 2
  fruit = "Apple"
  tags = @["Design", "Q3"]
  selectedTab = 1
  accordionOpen = true
  commandQuery = ""
  progress = 65.0
  toastVisible = false
  popoverOpen = false
  overflowOpen = false
  modalOpen = false
  drawerOpen = false
  sheetOpen = false
  slide = 0
  textBoxStates.clear()
  dropDownStates.clear()
  scrubberStates.clear()
  frameStates.clear()

proc testCatalog() =
  ## Checks that every page contains six named patterns.
  doAssert PatternSpecs.len == 30
  for page in PatternCategory:
    var count = 0
    for pattern in PatternKind:
      if PatternSpecs[pattern].category == page:
        inc count
    doAssert count == 6, page.categoryName & " should contain six patterns."

proc testInitialPage() =
  ## Checks that the initial controls page renders its named examples.
  resetState()
  window.pumpFrame(sk)
  doAssert sk.semantic.root.findByText("Form Field") != nil
  doAssert sk.semantic.root.findByText(
    "Switch, Checkbox, and Radio"
  ) != nil
  doAssert sk.semantic.root.findByText("Segmented Control") != nil
  doAssert sk.semantic.root.findByText("Slider and Stepper") != nil
  doAssert sk.semantic.root.findByText(
    "Combobox (Autocomplete / Typeahead)"
  ) != nil
  doAssert sk.semantic.root.findByText("Token Field") != nil

proc testAllPages() =
  ## Checks that every named pattern renders with visible geometry.
  resetState()
  for page in PatternCategory:
    category = page
    window.pumpFrame(sk)
    for pattern in PatternKind:
      if PatternSpecs[pattern].category == page:
        let node = sk.semantic.root.findByText(
          PatternSpecs[pattern].name
        )
        doAssert node != nil, PatternSpecs[pattern].name & " should render."
        doAssert node.rect.w > 0
        doAssert node.rect.h > 0

proc testTokenRemoval() =
  ## Checks that removing a token does not invalidate its render loop.
  resetState()
  window.pumpFrame(sk)
  window.clickButton(sk, "Design x")
  doAssert tags == @["Q3"]

proc testCategoryNavigation() =
  ## Checks that category controls replace the visible pattern page.
  window.clickText(sk, "Navigation", "RadioButton")
  doAssert category == NavigationPage
  doAssert sk.semantic.root.findByText("Breadcrumbs") != nil
  doAssert sk.semantic.root.findByText("Command Palette") != nil
  doAssert sk.semantic.root.findByText("Form Field") == nil

proc testModalDialog() =
  ## Checks the modal trigger, scrim, and cancel action.
  window.clickText(sk, "Overlays", "RadioButton")
  window.clickButton(sk, "Open modal dialog")
  doAssert modalOpen
  doAssert sk.semantic.root.findByName(
    "overlay scrim",
    "Rectangle"
  ) != nil
  doAssert sk.semantic.root.findByText("Delete file?") != nil
  window.clickButton(sk, "Cancel")
  doAssert not modalOpen

proc testToast() =
  ## Checks the non-blocking toast trigger and dismissal.
  window.clickText(sk, "Feedback", "RadioButton")
  window.clickButton(sk, "Save changes")
  doAssert toastVisible
  doAssert sk.semantic.root.findByText("Changes saved") != nil
  window.clickButton(sk, "Dismiss toast")
  doAssert not toastVisible

echo "Testing UI pattern gallery."
testCatalog()
testInitialPage()
testAllPages()
testTokenRemoval()
testCategoryNavigation()
testModalDialog()
testToast()
echo "UI pattern gallery tests passed."
