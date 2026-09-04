## Named UI patterns built from Silky primitives.
## Vocabulary reference: https://namethatui.com/

import
  std/strformat,
  bumpy, vmath, chroma, pixie,
  silky

type
  PatternCategory = enum
    ControlsPage
    NavigationPage
    FeedbackPage
    OverlaysPage
    LayoutsPage

  PatternKind = enum
    FormField
    ChoiceControls
    SegmentedControl
    SliderAndStepper
    Combobox
    TokenField
    SiteHeader
    Breadcrumbs
    Tabs
    Sidebar
    Accordion
    CommandPalette
    ProgressIndicators
    Toast
    Skeleton
    EmptyState
    Labels
    FocusRing
    Tooltip
    Popover
    OverflowMenu
    ModalDialog
    NavigationDrawer
    BottomSheet
    Card
    SplitView
    Inspector
    Carousel
    BentoGrid
    Masonry

  PatternSpec = object
    name*: string
    category*: PatternCategory
    description*: string

const
  BackgroundColor = parseHtmlColor("#111827").rgbx
  CardColor = parseHtmlColor("#1F2937").rgbx
  MutedColor = parseHtmlColor("#9CA3AF").rgbx
  AccentColor = parseHtmlColor("#60A5FA").rgbx
  AccentSoftColor = parseHtmlColor("#1E3A5F").rgbx
  ScrimColor = rgbx(3, 7, 18, 210)
  CardWidth = 580.0'f
  CardHeight = 194.0'f
  CardGap = 16.0'f
  PatternSpecs: array[PatternKind, PatternSpec] = [
    PatternSpec(
      name: "Form Field",
      category: ControlsPage,
      description: "A label, input, helper text, and error state."
    ),
    PatternSpec(
      name: "Switch, Checkbox, and Radio",
      category: ControlsPage,
      description: "On/off, independent, and single-choice controls."
    ),
    PatternSpec(
      name: "Segmented Control",
      category: ControlsPage,
      description: "A connected row with one persistent selection."
    ),
    PatternSpec(
      name: "Slider and Stepper",
      category: ControlsPage,
      description: "Continuous dragging beside discrete increments."
    ),
    PatternSpec(
      name: "Combobox (Autocomplete / Typeahead)",
      category: ControlsPage,
      description: "An input paired with selectable suggestions."
    ),
    PatternSpec(
      name: "Token Field",
      category: ControlsPage,
      description: "An input that turns values into removable tokens."
    ),
    PatternSpec(
      name: "Site Header and Navigation Bar",
      category: NavigationPage,
      description: "The top region and the page links nested inside it."
    ),
    PatternSpec(
      name: "Breadcrumbs",
      category: NavigationPage,
      description: "A trail from the current view to its ancestors."
    ),
    PatternSpec(
      name: "Tabs",
      category: NavigationPage,
      description: "Labels that switch one shared content region."
    ),
    PatternSpec(
      name: "Sidebar (Source List)",
      category: NavigationPage,
      description: "A persistent navigation column beside the content."
    ),
    PatternSpec(
      name: "Accordion (Disclosure)",
      category: NavigationPage,
      description: "Headings that expand and collapse their content."
    ),
    PatternSpec(
      name: "Command Palette",
      category: NavigationPage,
      description: "A keyboard-first launcher for actions and places."
    ),
    PatternSpec(
      name: "Progress Ring, Spinner, and Progress Bar",
      category: FeedbackPage,
      description: "Determinate and indeterminate progress feedback."
    ),
    PatternSpec(
      name: "Toast (Snackbar)",
      category: FeedbackPage,
      description: "A brief non-blocking message after an action."
    ),
    PatternSpec(
      name: "Skeleton Loading",
      category: FeedbackPage,
      description: "Placeholder geometry for predictable content."
    ),
    PatternSpec(
      name: "Empty State",
      category: FeedbackPage,
      description: "Guidance shown when a view has no content yet."
    ),
    PatternSpec(
      name: "Badge, Chip, Pill, and Tag",
      category: FeedbackPage,
      description: "Compact labels with different roles and behavior."
    ),
    PatternSpec(
      name: "Focus Ring",
      category: FeedbackPage,
      description: "The outline identifying the keyboard target."
    ),
    PatternSpec(
      name: "Tooltip",
      category: OverlaysPage,
      description: "A small hint anchored to a hovered control."
    ),
    PatternSpec(
      name: "Popover",
      category: OverlaysPage,
      description: "A rich anchored overlay with interactive content."
    ),
    PatternSpec(
      name: "Overflow and Context Menu",
      category: OverlaysPage,
      description: "Secondary actions revealed near their target."
    ),
    PatternSpec(
      name: "Modal Dialog and Scrim",
      category: OverlaysPage,
      description: "A blocking task over a dimmed application surface."
    ),
    PatternSpec(
      name: "Navigation Drawer",
      category: OverlaysPage,
      description: "A navigation panel that slides from an edge."
    ),
    PatternSpec(
      name: "Bottom Sheet",
      category: OverlaysPage,
      description: "A task surface attached to the bottom edge."
    ),
    PatternSpec(
      name: "Card",
      category: LayoutsPage,
      description: "A bounded surface grouping related content."
    ),
    PatternSpec(
      name: "Split View",
      category: LayoutsPage,
      description: "Resizable panes divided inside one workspace."
    ),
    PatternSpec(
      name: "Inspector Panel",
      category: LayoutsPage,
      description: "A side panel for the current selection's details."
    ),
    PatternSpec(
      name: "Carousel",
      category: LayoutsPage,
      description: "Slides paged with arrows and position controls."
    ),
    PatternSpec(
      name: "Bento Grid",
      category: LayoutsPage,
      description: "A compact grid with mixed tile sizes."
    ),
    PatternSpec(
      name: "Masonry Layout",
      category: LayoutsPage,
      description: "Uneven cards packed into gap-free columns."
    )
  ]
  FruitOptions = ["Apple", "Apricot", "Banana", "Mango"]
  SlideNames = ["Dunes", "Reef", "Meadow"]

let builder = newAtlasBuilder(1024, 4)
builder.addDir("data/", "data/")
builder.addFont("data/IBMPlexSans-Regular.ttf", "Title", 22.0)
builder.addFont("data/IBMPlexSans-Regular.ttf", "Default", 16.0)
builder.write("dist/atlas.png")

let window = newWindow(
  "UI Pattern Gallery",
  ivec2(1280, 800),
  vsync = false
)
makeContextCurrent(window)
loadExtensions()

let sk = newSilky(window, "dist/atlas.png")

sk.theme.defaultTextColor = parseHtmlColor("#F9FAFB").rgbx
sk.theme.textColor = parseHtmlColor("#F9FAFB").rgbx
sk.theme.textH1Color = parseHtmlColor("#F9FAFB").rgbx
sk.theme.disabledTextColor = MutedColor
sk.theme.frameFocusColor = AccentColor
sk.theme.menuItemBgColor = CardColor
sk.theme.menuPopupSelectedColor = AccentSoftColor

window.runeInputEnabled = true
window.onRune = proc(rune: Rune) =
  sk.inputRunes.add(rune)

var
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

proc categoryName(category: PatternCategory): string =
  ## Returns the short label for one gallery page.
  case category
  of ControlsPage:
    "Controls"
  of NavigationPage:
    "Navigation"
  of FeedbackPage:
    "Feedback"
  of OverlaysPage:
    "Overlays"
  of LayoutsPage:
    "Layouts"

proc slotRect(slot: int): Rect =
  ## Returns a two-column gallery rectangle for a page slot.
  let
    column = slot mod 2
    row = slot div 2
  rect(
    column.float32 * (CardWidth + CardGap),
    row.float32 * (CardHeight + CardGap),
    CardWidth,
    CardHeight
  )

template patternCard(
  pattern: PatternKind,
  slot: int,
  body: untyped
) =
  ## Draws one named pattern and its live miniature example.
  let cardRect = slotRect(slot)
  group "pattern card " & $pattern:
    box cardRect.x, cardRect.y, cardRect.w, cardRect.h
    patch "frame.9patch", 6
    tint CardColor
    horizontalPadding 14
    verticalPadding 12
    itemSpacing 7
    text "pattern title " & $pattern:
      characters PatternSpecs[pattern].name
      font "Title"
    text "pattern description " & $pattern:
      characters PatternSpecs[pattern].description
      tint MutedColor
    body

proc drawFormField() =
  ## Draws a labeled text field with helper text.
  text "email label":
    characters "Email *"
  textInput "pattern email", email
  text "email helper":
    characters "We only use this address to sign you in."
    tint MutedColor

proc drawChoiceControls() =
  ## Draws on/off, independent, and exclusive choices.
  group "choice controls row":
    box 540, 34
    layout LeftToRight
    itemSpacing 18
    checkBox "Notifications", notifications
    radioButton "Email", contactMethod, 1
    radioButton "SMS", contactMethod, 2

proc drawSegmentedControl() =
  ## Draws a one-of-many connected-style control.
  group "segmented control row":
    box 540, 34
    layout LeftToRight
    itemSpacing 10
    radioButton "Left", alignment, 1
    radioButton "Center", alignment, 2
    radioButton "Right", alignment, 3

proc drawSliderAndStepper() =
  ## Draws continuous and discrete numeric controls.
  scrubber "volume", volume, 0.0, 100.0, &"{volume:>3.0f}"
  group "stepper row":
    box 540, 34
    layout LeftToRight
    itemSpacing 8
    button "-":
      copies = max(0, copies - 1)
    text "stepper value":
      characters &"Copies: {copies}"
    button "+":
      inc copies

proc drawCombobox() =
  ## Draws a selectable suggestion field.
  text "combobox label":
    characters "Favorite fruit"
  dropDown fruit, FruitOptions

proc drawTokenField() =
  ## Draws removable values in a compact input-like row.
  var removeIndex = -1
  group "token field row":
    box 540, 38
    layout LeftToRight
    itemSpacing 8
    for i in 0 ..< tags.len:
      let index = i
      button tags[i] & " x":
        removeIndex = index
    button "+ Tag":
      tags.add("New")
  if removeIndex >= 0:
    tags.delete(removeIndex)

proc drawSiteHeader() =
  ## Draws a header containing its navigation bar.
  group "site header example":
    box 540, 40
    patch "frame.9patch", 6
    tint AccentSoftColor
    horizontalPadding 10
    verticalPadding 5
    layout LeftToRight
    itemSpacing 14
    text "site name":
      characters "Acme"
      font "Title"
    button "Home":
      discard
    button "Docs":
      discard
    button "Pricing":
      discard

proc drawBreadcrumbs() =
  ## Draws a hierarchy trail with separators.
  group "breadcrumbs row":
    box 540, 36
    layout LeftToRight
    itemSpacing 8
    button "Home":
      discard
    text "breadcrumb separator one":
      characters "/"
      tint MutedColor
    button "Components":
      discard
    text "breadcrumb separator two":
      characters "/"
      tint MutedColor
    text "breadcrumb current":
      characters "Buttons"

proc drawTabs() =
  ## Draws tabs controlling one shared panel.
  group "tabs row":
    box 540, 32
    layout LeftToRight
    itemSpacing 10
    radioButton "Overview", selectedTab, 1
    radioButton "Insights", selectedTab, 2
  text "tab panel":
    characters(
      if selectedTab == 1:
        "Weekly activity: 1,248"
      else:
        "Insights are up 12% this week."
    )

proc drawSidebar() =
  ## Draws a source list beside a content surface.
  group "sidebar example":
    box 540, 76
    layout LeftToRight
    itemSpacing 12
    group "sidebar list":
      box 170, 76
      patch "frame.9patch", 6
      tint AccentSoftColor
      horizontalPadding 8
      verticalPadding 5
      text "sidebar heading":
        characters "Favorites"
      text "sidebar items":
        characters "Recents   Documents"
    group "sidebar content":
      box 350, 76
      patch "frame.9patch", 6
      horizontalPadding 10
      verticalPadding 8
      text "sidebar content title":
        characters "Documents"

proc drawAccordion() =
  ## Draws an expandable disclosure section.
  button(
    if accordionOpen:
      "- What is a component?"
    else:
      "+ What is a component?"
  ):
    accordionOpen = not accordionOpen
  if accordionOpen:
    text "accordion answer":
      characters "A reusable piece of structure and behavior."

proc drawCommandPalette() =
  ## Draws a compact keyboard-first command launcher.
  textInput "command query", commandQuery
  group "command suggestions":
    box 540, 34
    layout LeftToRight
    itemSpacing 8
    button "New project":
      discard
    button "Settings":
      discard
    text "command shortcut":
      characters "Command K"
      tint MutedColor

proc drawProgressIndicators() =
  ## Draws determinate and indeterminate progress feedback.
  progressBar progress, 0, 100
  group "progress labels":
    box 540, 28
    layout LeftToRight
    itemSpacing 18
    text "progress percent":
      characters &"Progress bar: {progress:>3.0f}%"
    text "spinner label":
      characters "Spinner: working..."
      tint MutedColor

proc drawToast() =
  ## Draws an action that produces a dismissible toast.
  button "Save changes":
    toastVisible = true
  text "toast hint":
    characters "The message appears without blocking the page."
    tint MutedColor

proc drawSkeleton() =
  ## Draws placeholder shapes matching pending content.
  rectangle "skeleton avatar":
    box 0, 98, 52, 52
    tint parseHtmlColor("#4B5563").rgbx
  rectangle "skeleton line one":
    box 68, 102, 300, 14
    tint parseHtmlColor("#4B5563").rgbx
  rectangle "skeleton line two":
    box 68, 128, 220, 12
    tint parseHtmlColor("#374151").rgbx

proc drawEmptyState() =
  ## Draws guidance and a primary action for an empty view.
  text "empty state title":
    characters "No projects yet"
    font "Title"
  text "empty state body":
    characters "Create one to start organizing your work."
    tint MutedColor
  button "New project":
    discard

proc drawLabels() =
  ## Draws compact labels with several common roles.
  group "labels row":
    box 540, 36
    layout LeftToRight
    itemSpacing 8
    button "Badge 7":
      discard
    button "Chip Design":
      discard
    button "Pill Active":
      discard
    button "Tag Web":
      discard

proc drawFocusRing() =
  ## Draws a keyboard target with an explicit focus outline.
  group "focus ring example":
    box 240, 48
    patch "frame.9patch", 6
    tint AccentColor
    horizontalPadding 6
    verticalPadding 6
    button "Focused action":
      discard
  text "focus ring hint":
    characters "Use a focus ring for keyboard navigation."
    tint MutedColor

proc drawTooltip() =
  ## Draws a tooltip anchored to an icon button.
  group "tooltip example row":
    box 540, 36
    layout LeftToRight
    itemSpacing 14
    iconButton "heart":
      discard
    if sk.hover and sk.shouldShowTooltip:
      tooltip "Add to favorites"
    text "tooltip instruction":
      characters "Hover the heart for a tooltip."

proc drawPopover() =
  ## Draws an anchored overlay containing controls.
  button "Filters":
    popoverOpen = not popoverOpen
  if popoverOpen:
    group "filters popover":
      box 150, 100, 300, 72
      patch "frame.9patch", 6
      tint AccentSoftColor
      horizontalPadding 10
      verticalPadding 8
      text "popover title":
        characters "Filter projects"
      checkBox "Active only", notifications

proc drawOverflowMenu() =
  ## Draws a compact overflow menu for secondary actions.
  button "More ...":
    overflowOpen = not overflowOpen
  if overflowOpen:
    group "overflow actions":
      box 150, 100, 300, 72
      patch "frame.9patch", 6
      tint AccentSoftColor
      horizontalPadding 8
      verticalPadding 5
      layout LeftToRight
      itemSpacing 8
      button "Rename":
        discard
      button "Duplicate":
        discard
      button "Delete":
        discard

proc drawModalDialog() =
  ## Draws the trigger for a blocking dialog and its scrim.
  button "Open modal dialog":
    modalOpen = true
  text "modal hint":
    characters "The scrim separates the task from the page."
    tint MutedColor

proc drawNavigationDrawer() =
  ## Draws the trigger for an edge-attached navigation drawer.
  button "Open navigation drawer":
    drawerOpen = true
  text "drawer hint":
    characters "Drawers enter from a vertical screen edge."
    tint MutedColor

proc drawBottomSheet() =
  ## Draws the trigger for a bottom-attached task surface.
  button "Open bottom sheet":
    sheetOpen = true
  text "sheet hint":
    characters "Sheets are useful for compact contextual tasks."
    tint MutedColor

proc drawCard() =
  ## Draws media, content, and actions on one surface.
  group "sample card":
    box 540, 80
    patch "frame.9patch", 6
    tint AccentSoftColor
    horizontalPadding 10
    verticalPadding 8
    layout LeftToRight
    itemSpacing 14
    rectangle "card media":
      box 96, 60
      tint AccentColor
    group "card content":
      box 390, 60
      text "card title":
        characters "Field notes"
        font "Title"
      text "card body":
        characters "A title, body, media, and action belong together."

proc drawSplitView() =
  ## Draws two panes with a clear divider.
  group "split view example":
    box 540, 78
    layout LeftToRight
    itemSpacing 6
    rectangle "split list":
      box 180, 78
      tint AccentSoftColor
      text "split list text":
        box 10, 10, 150, 40
        characters "Inbox\nSent\nDrafts"
    rectangle "split detail":
      box 350, 78
      tint parseHtmlColor("#273449").rgbx
      text "split detail text":
        box 12, 12, 320, 24
        characters "Message detail"

proc drawInspector() =
  ## Draws an inspector beside a selected canvas item.
  group "inspector example":
    box 540, 80
    layout LeftToRight
    itemSpacing 8
    rectangle "inspector canvas":
      box 340, 80
      tint parseHtmlColor("#273449").rgbx
      text "inspector selection":
        box 100, 28, 140, 24
        characters "Selected card"
        textAlign CenterAlign, MiddleAlign
    group "inspector panel":
      box 190, 80
      patch "frame.9patch", 6
      tint AccentSoftColor
      horizontalPadding 8
      verticalPadding 5
      text "inspector title":
        characters "Inspector"
      text "inspector fields":
        characters "Fill   Border   Shadow"

proc drawCarousel() =
  ## Draws slide content with previous and next controls.
  group "carousel controls":
    box 540, 34
    layout LeftToRight
    itemSpacing 10
    button "Previous":
      slide = (slide + SlideNames.len - 1) mod SlideNames.len
    text "carousel slide":
      box 210, 28
      characters SlideNames[slide] & "  " & $(slide + 1) & " / 3"
      textAlign CenterAlign, MiddleAlign
    button "Next":
      slide = (slide + 1) mod SlideNames.len

proc drawBentoGrid() =
  ## Draws a grid with tiles spanning different cells.
  rectangle "bento revenue":
    box 0, 96, 250, 70
    tint AccentSoftColor
    text "bento revenue text":
      box 12, 12, 220, 40
      characters "Revenue\n$48.2k"
  rectangle "bento users":
    box 260, 96, 140, 70
    tint parseHtmlColor("#273449").rgbx
    text "bento users text":
      box 10, 12, 120, 40
      characters "Users\n2.4k"
  rectangle "bento growth":
    box 410, 96, 140, 70
    tint parseHtmlColor("#164E63").rgbx
    text "bento growth text":
      box 10, 12, 120, 40
      characters "Growth\n+12%"

proc drawMasonry() =
  ## Draws uneven cards packed into columns.
  rectangle "masonry one":
    box 0, 96, 128, 64
    tint AccentSoftColor
  rectangle "masonry two":
    box 138, 96, 128, 42
    tint parseHtmlColor("#273449").rgbx
  rectangle "masonry three":
    box 276, 96, 128, 70
    tint parseHtmlColor("#164E63").rgbx
  rectangle "masonry four":
    box 414, 96, 128, 52
    tint parseHtmlColor("#3F3F46").rgbx

proc drawPattern(pattern: PatternKind, slot: int) =
  ## Draws one pattern card using explicit enum dispatch.
  patternCard pattern, slot:
    case pattern
    of FormField:
      drawFormField()
    of ChoiceControls:
      drawChoiceControls()
    of SegmentedControl:
      drawSegmentedControl()
    of SliderAndStepper:
      drawSliderAndStepper()
    of Combobox:
      drawCombobox()
    of TokenField:
      drawTokenField()
    of SiteHeader:
      drawSiteHeader()
    of Breadcrumbs:
      drawBreadcrumbs()
    of Tabs:
      drawTabs()
    of Sidebar:
      drawSidebar()
    of Accordion:
      drawAccordion()
    of CommandPalette:
      drawCommandPalette()
    of ProgressIndicators:
      drawProgressIndicators()
    of Toast:
      drawToast()
    of Skeleton:
      drawSkeleton()
    of EmptyState:
      drawEmptyState()
    of Labels:
      drawLabels()
    of FocusRing:
      drawFocusRing()
    of Tooltip:
      drawTooltip()
    of Popover:
      drawPopover()
    of OverflowMenu:
      drawOverflowMenu()
    of ModalDialog:
      drawModalDialog()
    of NavigationDrawer:
      drawNavigationDrawer()
    of BottomSheet:
      drawBottomSheet()
    of Card:
      drawCard()
    of SplitView:
      drawSplitView()
    of Inspector:
      drawInspector()
    of Carousel:
      drawCarousel()
    of BentoGrid:
      drawBentoGrid()
    of Masonry:
      drawMasonry()

proc drawCategory(category: PatternCategory) =
  ## Draws all six patterns assigned to the selected category.
  var slot = 0
  for pattern in PatternKind:
    if PatternSpecs[pattern].category == category:
      drawPattern(pattern, slot)
      inc slot

proc dismissBlockingOverlays() =
  ## Dismisses every blocking overlay in the gallery.
  modalOpen = false
  drawerOpen = false
  sheetOpen = false

proc drawBlockingOverlays() =
  ## Draws modal, drawer, and sheet examples above the gallery.
  if modalOpen or drawerOpen or sheetOpen:
    rectangle "overlay scrim":
      box 0, 0, sk.size.x, sk.size.y
      tint ScrimColor
      onClick:
        dismissBlockingOverlays()

  if modalOpen:
    group "modal dialog":
      box (sk.size.x - 420) * 0.5, (sk.size.y - 220) * 0.5, 420, 220
      patch "frame.9patch", 6
      tint CardColor
      horizontalPadding 24
      verticalPadding 22
      itemSpacing 12
      text "modal title":
        characters "Delete file?"
        font "Title"
      text "modal body":
        characters "This blocking action cannot be undone."
      group "modal actions":
        box 360, 36
        layout LeftToRight
        itemSpacing 10
        button "Cancel":
          modalOpen = false
        button "Delete":
          modalOpen = false

  if drawerOpen:
    group "navigation drawer":
      box sk.size.x - 360, 0, 360, sk.size.y
      patch "frame.9patch", 6
      tint CardColor
      horizontalPadding 24
      verticalPadding 24
      itemSpacing 14
      text "drawer title":
        characters "Navigation"
        font "Title"
      button "Home":
        drawerOpen = false
      button "Projects":
        drawerOpen = false
      button "Settings":
        drawerOpen = false
      button "Close drawer":
        drawerOpen = false

  if sheetOpen:
    group "bottom sheet":
      box 0, sk.size.y - 230, sk.size.x, 230
      patch "frame.9patch", 6
      tint CardColor
      horizontalPadding 32
      verticalPadding 24
      itemSpacing 12
      text "sheet title":
        characters "Share with..."
        font "Title"
      text "sheet body":
        characters "Choose a teammate or copy a public link."
      group "sheet actions":
        box 520, 36
        layout LeftToRight
        itemSpacing 10
        button "Copy link":
          sheetOpen = false
        button "Close sheet":
          sheetOpen = false

proc drawToastOverlay() =
  ## Draws a non-blocking toast over the gallery.
  if not toastVisible:
    return
  group "toast snackbar":
    box sk.size.x - 350, 74, 320, 72
    patch "frame.9patch", 6
    tint AccentSoftColor
    horizontalPadding 14
    verticalPadding 10
    itemSpacing 6
    text "toast text":
      characters "Changes saved"
      font "Title"
    button "Dismiss toast":
      toastVisible = false

window.onFrame = proc() =
  sk.beginUI(window, window.size)
  sk.clearScreen(BackgroundColor)

  ui:
    rectangle "page header":
      box 0, 0, sk.size.x, 64
      tint parseHtmlColor("#0B1220").rgbx
      text "gallery title":
        box 24, 10, 300, 28
        characters "UI Pattern Gallery"
        font "Title"
      text "gallery source":
        box 326, 14, 470, 24
        characters "30 named patterns inspired by namethatui.com"
        tint MutedColor

    group "category tabs":
      box 24, 72, sk.size.x - 48, 34
      layout LeftToRight
      itemSpacing 18
      for page in PatternCategory:
        radioButton page.categoryName, category, page

    frame "pattern gallery":
      box 24, 116, sk.size.x - 48, sk.size.y - 140
      horizontalPadding 16
      verticalPadding 16
      drawCategory(category)

    drawToastOverlay()
    drawBlockingOverlays()

  progress += 0.03
  if progress > 100:
    progress = 0

  sk.endUi()
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()
