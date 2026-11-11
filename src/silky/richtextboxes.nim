import
  std/[tables, unicode, times],
  vmath, bumpy, chroma,
  silky/atlas, silky/internal/inputs, silky/textboxes

when defined(silkyTesting):
  import silky/[semantics, testing, profiles]
else:
  import silky/[contexts, profiles], windy

const
  LF = Rune(10)
  Space = Rune(32)
  Tab = Rune(9)
  DoubleClickTime = 0.4
  SelectionColor = rgbx(30, 60, 130, 128)

when defined(macos):
  const TextBoxScrollSpeed = 10.0f
else:
  const TextBoxScrollSpeed = -10.0f

type
  TextSpan* = object
    ## Read-only formatting over a half-open range of rune offsets.
    first*, last*: int
    font*: string
    color*: ColorRGBX
    background*: ColorRGBX
    strikethrough*: bool
    linkId*: int
      ## Matching positive IDs group the styled parts of one hoverable link.

  TextBlock* = object
    ## A styled block over a half-open range of shared rune offsets.
    first*, last*: int
    font*: string
    padding*: Vec2
    spacing*: float32
    patch*: string
    patchBorder*: int
    label*, labelFont*: string
    labelColor*: ColorRGBX
    labelSpacing*: float32
    ruleColor*: ColorRGBX
    ruleThickness*: float32
      ## Positive thickness turns an empty block into a horizontal rule.
    quoteDepth*, quoteContinue*: int
      ## Continued quote levels also draw their borders through spacing.
    quoteIndent*: float32 = 16
    quoteColor*: ColorRGBX
    quoteThickness*: float32 = 2

  BlockLayout = object
    bounds: Rect
    ruleBounds: Rect
    quoteBounds: Rect
    labelPosition: Vec2
    labelFont: string

  TextRun = object
    text: string
    font: string
    position: Vec2
    bounds: Rect
    span: int

  RichTextBoxState* = ref object
    ## Read-only styled content with one shared plain-text selection state.
    editor*: TextBoxState
    spans*: seq[TextSpan]
    blocks*: seq[TextBlock]
    activatedSpan*: int = -1
    hoveredSpan*: int = -1
    runeSpans: seq[int]
    runs: seq[TextRun]
    blockLayouts: seq[BlockLayout]
    lastFont: string
    focusEpoch: uint64
    pressedSpan: int = -1
    pressPosition: Vec2
    spanDragged: bool

var
  richTextBoxStates*: Table[string, RichTextBoxState]

proc newRichTextBoxState*(text = "", wordWrap = true): RichTextBoxState =
  ## Creates a read-only document with its own selection and layout cache.
  result = RichTextBoxState(
    editor: TextBoxState(wordWrap: wordWrap, enabled: false)
  )
  result.editor.setText(text)

proc getText*(state: RichTextBoxState): string =
  ## Returns the underlying selectable text without formatting markers.
  state.editor.getText()

proc sameText*(state: RichTextBoxState, text: string): bool =
  ## Compares the selectable text without allocating.
  state.editor.sameText(text)

proc setText*(
  state: RichTextBoxState,
  text: string,
  preserveSelection = false
) =
  ## Replaces content while optionally retaining a streamed selection.
  state.editor.setText(text, preserveSelection)

proc innerHeight*(state: RichTextBoxState): float32 =
  ## Returns the measured height of the complete styled document.
  state.editor.innerHeight

proc computeLayout*(
  state: RichTextBoxState,
  fonts: Table[string, FontAtlas],
  baseFont: string,
  maxWidth: float32
)

proc computeBlocks(
  state: RichTextBoxState,
  fonts: Table[string, FontAtlas],
  baseFont: string,
  maxWidth: float32
) =
  ## Combines block layouts into one selectable document and native run list.
  state.editor.positionedLayout = true
  state.editor.lineHeight = fonts[baseFont].lineHeight
  state.editor.lastMaxWidth = maxWidth
  state.editor.layout.setLen(state.editor.runes.len)
  state.runeSpans.setLen(state.editor.runes.len)
  state.runs.setLen(0)
  state.blockLayouts.setLen(0)
  state.editor.layoutHeight = 0
  for index in state.runeSpans.mitems:
    index = -1
  var
    covered = 0
    previousEnd = rect(0, 0, 0, state.editor.lineHeight)
  for item in state.blocks:
    let
      first = clamp(item.first, covered, state.editor.runes.len)
      last = clamp(item.last, first, state.editor.runes.len)
      width = max(0.0'f, maxWidth)
      depth = max(0, item.quoteDepth)
      padding = vec2(
        if depth > 0:
          min(max(0.0'f, item.padding.x), width / 2)
        else:
          max(0.0'f, item.padding.x),
        max(0.0'f, item.padding.y)
      )
      quoteInset = min(
        max(0.0'f, width - padding.x * 2),
        depth.float32 * max(0.0'f, item.quoteIndent)
      )
      blockWidth = width - quoteInset
    for i in covered ..< first:
      state.editor.layout[i] = previousEnd
    if first == last and item.ruleThickness > 0:
      let
        origin = vec2(
          quoteInset + padding.x,
          state.editor.layoutHeight + padding.y
        )
        height = item.ruleThickness + padding.y * 2
      state.blockLayouts.add(BlockLayout(
        bounds: rect(quoteInset, state.editor.layoutHeight, blockWidth, height),
        ruleBounds: rect(
          origin,
          vec2(max(0.0'f, blockWidth - padding.x * 2), item.ruleThickness)
        ),
        quoteBounds: rect(
          padding.x,
          state.editor.layoutHeight,
          max(0.0'f, width - padding.x * 2),
          height
        )
      ))
      state.editor.layoutCursor = rect(origin, vec2(0))
      state.editor.layoutHeight += height + max(0.0'f, item.spacing)
      previousEnd = state.editor.layoutCursor
      covered = last
      continue
    let
      font =
        if item.font in fonts:
          item.font
        else:
          baseFont
      labelFont =
        if item.labelFont in fonts:
          item.labelFont
        else:
          baseFont
      labelHeight =
        if item.label.len > 0:
          fonts[labelFont].lineHeight + max(0.0'f, item.labelSpacing)
        else:
          0.0'f
      origin = vec2(
        quoteInset + padding.x,
        state.editor.layoutHeight + padding.y + labelHeight
      )
      local = RichTextBoxState(
        editor: TextBoxState(
          runes: state.editor.runes[first ..< last],
          wordWrap: state.editor.wordWrap,
          enabled: false
        ),
        spans: @[TextSpan()]
      )
    var spanIndices = @[-1]
    for index, span in state.spans:
      if span.first < last and span.last > first:
        var relative = span
        relative.first = max(first, span.first) - first
        relative.last = min(last, span.last) - first
        local.spans.add(relative)
        spanIndices.add(index)
    local.computeLayout(fonts, font, max(0.0'f, blockWidth - padding.x * 2))
    var contentHeight = local.editor.lineHeight
    for i, bounds in local.editor.layout:
      state.editor.layout[first + i] = rect(origin + bounds.xy, bounds.wh)
      let span = local.runeSpans[i]
      if span >= 0:
        state.runeSpans[first + i] = spanIndices[span]
    for run in local.runs.mitems:
      run.position += origin
      run.bounds.x += origin.x
      run.bounds.y += origin.y
      if run.span >= 0:
        run.span = spanIndices[run.span]
      state.runs.add(run)
    state.editor.layoutCursor = rect(
      origin.x,
      origin.y,
      0,
      local.editor.lineHeight
    )
    if local.editor.layout.len > 0:
      let bounds = local.editor.layout[^1]
      contentHeight = bounds.y + bounds.h
      state.editor.layoutCursor = rect(
        origin.x + bounds.x + bounds.w,
        origin.y + bounds.y,
        0,
        bounds.h
      )
      if local.editor.runes[^1] == LF:
        contentHeight += local.editor.lineHeight
        state.editor.layoutCursor.x = origin.x
        state.editor.layoutCursor.y += local.editor.lineHeight
    let height = contentHeight + padding.y * 2 + labelHeight
    state.blockLayouts.add(BlockLayout(
      bounds: rect(quoteInset, state.editor.layoutHeight, blockWidth, height),
      quoteBounds: rect(
        padding.x, state.editor.layoutHeight, max(0.0'f, width - padding.x * 2),
        height
      ),
      labelPosition: vec2(
        quoteInset + padding.x, state.editor.layoutHeight + padding.y
      ),
      labelFont: labelFont
    ))
    state.editor.layoutHeight += height + max(0.0'f, item.spacing)
    previousEnd = state.editor.layoutCursor
    covered = last
  for i in covered ..< state.editor.runes.len:
    state.editor.layout[i] = previousEnd
  state.editor.dirty = false

proc computeLayout*(
  state: RichTextBoxState,
  fonts: Table[string, FontAtlas],
  baseFont: string,
  maxWidth: float32
) =
  ## Lays out styled text with the same glyph positions used for selection.
  state.lastFont = baseFont
  if state.blocks.len > 0:
    state.computeBlocks(fonts, baseFont, maxWidth)
    return
  state.editor.positionedLayout = false
  state.editor.layoutCursor = rect(0, 0, 0, 0)
  state.blockLayouts.setLen(0)
  state.editor.layoutHeight = 0
  if state.spans.len == 0:
    state.runeSpans.setLen(0)
    state.runs.setLen(0)
    state.editor.computeLayout(fonts[baseFont], maxWidth)
    return
  let base = fonts[baseFont]
  var
    resolvedFonts = @[base]
    fontNames = @[baseFont]
    baseline = base.ascent
    descent = base.descent
    lineGap = base.lineGap
  state.editor.lineHeight = base.lineHeight
  state.editor.lastMaxWidth = maxWidth
  state.editor.layout.setLen(0)
  state.runs.setLen(0)
  state.runeSpans.setLen(state.editor.runes.len)
  for index in state.runeSpans.mitems:
    index = -1
  for index, span in state.spans:
    let name =
      if span.font.len > 0 and span.font in fonts:
        span.font
      else:
        baseFont
    let font = fonts[name]
    resolvedFonts.add(font)
    fontNames.add(name)
    if span.first < state.editor.runes.len and span.last > max(0, span.first):
      state.editor.lineHeight = max(state.editor.lineHeight, font.lineHeight)
      baseline = max(baseline, font.ascent)
      descent = min(descent, font.descent)
      lineGap = max(lineGap, font.lineGap)
    for i in max(0, span.first) ..< min(span.last, state.editor.runes.len):
      state.runeSpans[i] = index
  state.editor.lineHeight = max(
    state.editor.lineHeight,
    baseline - descent + lineGap
  )
  var
    advances = newSeq[float32](state.editor.runes.len)
    kernings = newSeq[float32](state.editor.runes.len)
  for i, rune in state.editor.runes:
    if rune == LF:
      continue
    let font = resolvedFonts[state.runeSpans[i] + 1]
    var entry: ptr LetterEntry
    if rune == Tab:
      if font.lookupLetter(Space, 0, entry):
        advances[i] = entry.advance * 4
      continue
    if font.lookupLetter(rune, 0, entry):
      advances[i] = entry.advance
    if i + 1 < state.editor.runes.len and state.editor.runes[i + 1] != LF and
      font == resolvedFonts[state.runeSpans[i + 1] + 1]:
        kernings[i] = font.lookupKerning(rune, state.editor.runes[i + 1])
  var position = vec2(0, 0)
  for i, rune in state.editor.runes:
    if rune == LF:
      state.editor.layout.add(rect(
        position.x,
        position.y,
        0,
        state.editor.lineHeight
      ))
      position.x = 0
      position.y += state.editor.lineHeight
      continue
    if state.editor.wordWrap and maxWidth < float32.high:
      let wordStart = i == 0 or state.editor.runes[i - 1] in [Space, Tab, LF]
      if wordStart and rune notin [Space, Tab] and position.x > 0:
        var
          wordWidth = 0.0'f
          j = i
        while j < state.editor.runes.len and
          state.editor.runes[j] notin [Space, Tab, LF]:
            wordWidth += advances[j]
            if j + 1 < state.editor.runes.len and
              state.editor.runes[j + 1] notin [Space, Tab, LF]:
                wordWidth += kernings[j]
            inc j
        if position.x + wordWidth > maxWidth:
          position.x = 0
          position.y += state.editor.lineHeight
      if position.x > 0 and position.x + advances[i] > maxWidth:
        position.x = 0
        position.y += state.editor.lineHeight
    state.editor.layout.add(rect(
      position.x, position.y, advances[i], state.editor.lineHeight
    ))
    position.x += advances[i] + kernings[i]
  var i = 0
  while i < state.editor.runes.len:
    if state.editor.runes[i] in [LF, Tab]:
      inc i
      continue
    let
      first = i
      span = state.runeSpans[i]
      font = resolvedFonts[span + 1]
      bounds = state.editor.layout[i]
    var text = ""
    while i < state.editor.runes.len and
      state.editor.runes[i] notin [LF, Tab] and
      state.runeSpans[i] == span and state.editor.layout[i].y == bounds.y:
        text.add($state.editor.runes[i])
        inc i
    let last = state.editor.layout[i - 1]
    state.runs.add(TextRun(
      text: text,
      font: fontNames[span + 1],
      position: vec2(bounds.x, bounds.y + baseline - font.ascent),
      bounds: rect(
        bounds.x, bounds.y, last.x + last.w - bounds.x, bounds.h
      ),
      span: state.runeSpans[first]
    ))
  state.editor.dirty = false

proc spanAt(state: RichTextBoxState, position: Vec2): int =
  ## Finds a formatted span only when the pointer touches its glyph bounds.
  for i, bounds in state.editor.layout:
    if position.overlaps(bounds) and i < state.runeSpans.len:
      return state.runeSpans[i]
  -1

proc drawSpanBackgrounds(sk: Silky, state: RichTextBoxState, origin: Vec2) =
  ## Draws inline backgrounds before the native selection highlight.
  for run in state.runs:
    if run.span >= 0:
      let color = state.spans[run.span].background
      if color.a > 0:
        sk.drawRect(origin + run.bounds.xy, run.bounds.wh, color)

proc drawBlocks(
  sk: Silky,
  state: RichTextBoxState,
  origin: Vec2,
  defaultColor: ColorRGBX
) =
  ## Draws native block surfaces, borders, rules, and captions.
  for i, bounds in state.blockLayouts:
    let item = state.blocks[i]
    if item.patch.len > 0:
      sk.draw9Patch(
        item.patch,
        item.patchBorder,
        origin + bounds.bounds.xy,
        bounds.bounds.wh
      )
    if item.quoteDepth > 0 and item.quoteThickness > 0 and
      item.quoteColor.a > 0 and bounds.quoteBounds.w > 0:
        let
          scale = max(sk.uiScale, 0.001'f)
          indent = max(0.0'f, item.quoteIndent)
          position = origin + bounds.quoteBounds.xy
          limit = floor((position.x + bounds.quoteBounds.w) * scale) / scale
          top = round(position.y * scale) / scale
          thickness = max(1.0'f, round(item.quoteThickness * scale)) / scale
          continuation = clamp(item.quoteContinue, 0, item.quoteDepth)
        for level in 0 ..< item.quoteDepth:
          let
            left = round((position.x + level.float32 * indent) * scale) /
              scale
            width = min(thickness, limit - left)
          if width <= 0:
            break
          let
            spacing =
              if level < continuation:
                max(0.0'f, item.spacing)
              else:
                0.0'f
            bottom = round(
              (position.y + bounds.quoteBounds.h + spacing) * scale
            ) / scale
          sk.drawRect(
            vec2(left, top), vec2(width, bottom - top), item.quoteColor
          )
          if indent == 0:
            break
    if bounds.ruleBounds.h > 0:
      if bounds.ruleBounds.w > 0 and item.ruleColor.a > 0:
        let
          scale = max(sk.uiScale, 0.001'f)
          position = origin + bounds.ruleBounds.xy
          left = round(position.x * scale) / scale
          right = round((position.x + bounds.ruleBounds.w) * scale) / scale
          top = round(position.y * scale) / scale
          thickness = max(1.0'f, round(bounds.ruleBounds.h * scale)) / scale
        sk.drawRect(
          vec2(left, top), vec2(right - left, thickness), item.ruleColor
        )
      continue
    if item.label.len > 0:
      let color =
        if item.labelColor.a > 0:
          item.labelColor
        else:
          defaultColor
      discard sk.drawText(
        bounds.labelFont,
        item.label,
        origin + bounds.labelPosition,
        color,
        maxWidth = max(0.0'f, bounds.bounds.w - item.padding.x * 2)
      )

proc drawSpans(
  sk: Silky,
  state: RichTextBoxState,
  origin: Vec2,
  defaultColor: ColorRGBX
) =
  ## Draws cached runs at their measured positions without wrapping again.
  for run in state.runs:
    let color =
      if run.span >= 0 and state.spans[run.span].color.a > 0:
        state.spans[run.span].color
      else:
        defaultColor
    discard sk.drawText(
      run.font, run.text, origin + run.position, color, clip = false
    )
    if run.span >= 0:
      let
        span = state.spans[run.span]
        underline = state.hoveredSpan >= 0 and span.linkId > 0 and
          span.linkId == state.spans[state.hoveredSpan].linkId
      if span.strikethrough or underline:
        let
          font = sk.atlas.fonts[run.font]
          scale = max(sk.uiScale, 0.001'f)
          left = round((origin.x + run.bounds.x) * scale) / scale
          right = round((origin.x + run.bounds.x + run.bounds.w) * scale) /
            scale
          baseline = origin.y + run.position.y + font.ascent
          thickness = max(1.0'f, round(scale)) / scale
        if span.strikethrough:
          let top = round((baseline - font.size * 0.3'f) * scale) / scale
          sk.drawRect(vec2(left, top), vec2(right - left, thickness), color)
        if underline:
          let top = round((baseline + 1) * scale) / scale
          sk.drawRect(vec2(left, top), vec2(right - left, thickness), color)

proc richTextBox*(
  sk: Silky,
  window: Window,
  id, text: string,
  boxWidth, boxHeight: float32,
  wrapWords = true,
  spans: seq[TextSpan] = default(seq[TextSpan]),
  blocks: seq[TextBlock] = default(seq[TextBlock])
) {.measure.} =
  ## Draws a read-only styled document with one selection and link handling.
  if id notin richTextBoxStates:
    richTextBoxStates[id] = newRichTextBoxState(text, wrapWords)
  let
    state = richTextBoxStates[id]
    editor = state.editor
    inputs = sk.textInputs
  editor.enabled = false
  state.activatedSpan = -1
  state.hoveredSpan = -1
  if editor.focused and state.focusEpoch != inputs.focusEpoch:
    editor.focused = false
    editor.dragging = false
    editor.selector = editor.cursor
  if state.spans != spans:
    state.spans = spans
    editor.dirty = true
  if state.blocks != blocks:
    state.blocks = blocks
    editor.dirty = true
  if editor.wordWrap != wrapWords:
    editor.wordWrap = wrapWords
    editor.dirty = true
  if not state.sameText(text):
    state.setText(text, preserveSelection = true)
  let
    padding = sk.theme.padding.float32
    outerRect = rect(sk.at, vec2(boxWidth, boxHeight))
    innerRect = rect(
      sk.at.x + padding, sk.at.y + padding,
      boxWidth - padding * 2, boxHeight - padding * 2
    )
  editor.boxSize = innerRect.wh
  if editor.dirty or editor.lastMaxWidth != innerRect.w or
    state.lastFont != sk.textStyle:
      state.computeLayout(sk.atlas.fonts, sk.textStyle, innerRect.w)
  let
    shift = window.buttonDown[KeyLeftShift] or
      window.buttonDown[KeyRightShift]
    mouseVec = sk.mousePos
    mouseInside = mouseVec.overlaps(outerRect) and
      mouseVec.overlaps(sk.clipRect)
    onScrollbar = mouseInside and not mouseVec.overlaps(innerRect)
  if window.buttonPressed[MouseLeft]:
    state.pressedSpan = -1
    if mouseInside and not onScrollbar:
      editor.focused = true
      let
        localMouse = mouseVec - innerRect.xy + editor.scrollPos
        now = epochTime()
      if now - editor.lastClickTime < DoubleClickTime:
        inc editor.clickCount
      else:
        editor.clickCount = 1
      editor.lastClickTime = now
      case editor.clickCount
      of 1:
        editor.mouseAction(localMouse, click = true, shift = shift)
        editor.dragging = true
        if not shift:
          state.pressedSpan = state.spanAt(localMouse)
          state.pressPosition = mouseVec
          state.spanDragged = false
      of 2:
        editor.selectWord(localMouse)
      of 3:
        editor.selectParagraph(localMouse)
      else:
        editor.selectAll()
    elif not mouseInside:
      editor.focused = false
      editor.dragging = false
      editor.selector = editor.cursor
  if state.pressedSpan >= 0:
    let distance = mouseVec - state.pressPosition
    if distance.x * distance.x + distance.y * distance.y > 9:
      state.spanDragged = true
    if window.buttonReleased[MouseLeft]:
      let localMouse = mouseVec - innerRect.xy + editor.scrollPos
      if mouseInside and not state.spanDragged and
        editor.cursor == editor.selector and
        state.spanAt(localMouse) == state.pressedSpan:
          state.activatedSpan = state.pressedSpan
      state.pressedSpan = -1
    elif not window.buttonDown[MouseLeft]:
      state.pressedSpan = -1
  if editor.dragging and not editor.scrollingX and not editor.scrollingY:
    if window.buttonDown[MouseLeft] and not window.buttonPressed[MouseLeft]:
      let localMouse = mouseVec - innerRect.xy + editor.scrollPos
      editor.mouseAction(localMouse, click = false, shift = true)
    if window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]:
      editor.dragging = false
  inputs.submitInput(window, "rich-textbox:" & id, editor.focused, false)
  if editor.focused:
    state.focusEpoch = inputs.focusEpoch
    editor.handleSelectionInput(inputs)
  let maxScrollY = max(0.0'f, editor.innerHeight - innerRect.h)
  editor.scrollPos.y = clamp(editor.scrollPos.y, 0.0'f, maxScrollY)
  if editor.wordWrap:
    editor.scrollPos.x = 0
  else:
    editor.scrollPos.x = max(0.0'f, editor.scrollPos.x)
  let
    overVerticalBar = editor.innerHeight > innerRect.h and
      mouseVec.x >= outerRect.x + outerRect.w - 10
    overHorizontalBar = not editor.wordWrap and
      editor.innerWidth > innerRect.w and
      mouseVec.y >= outerRect.y + outerRect.h - 10
  if mouseInside and mouseVec.overlaps(innerRect) and
    not editor.scrollingX and not editor.scrollingY and
    not overVerticalBar and not overHorizontalBar:
      let index = state.spanAt(mouseVec - innerRect.xy + editor.scrollPos)
      if index >= 0 and state.spans[index].linkId > 0:
        state.hoveredSpan = index
        sk.cursor = Cursor(kind: PointerCursor)
  let textColor = sk.theme.disabledTextColor
  sk.draw9Patch(
    "textbox.disabled.9patch", sk.theme.textboxPatch, outerRect.xy, outerRect.wh
  )
  sk.pushClipRect(innerRect)
  let textOrigin = innerRect.xy - editor.scrollPos
  if state.blocks.len > 0:
    sk.drawBlocks(state, textOrigin, textColor)
  if state.spans.len > 0:
    sk.drawSpanBackgrounds(state, textOrigin)
  if editor.cursor != editor.selector:
    let selection = editor.selection
    for bounds in getSelectionRects(editor.layout, selection.a, selection.b):
      sk.drawRect(
        textOrigin + bounds.xy, bounds.wh, SelectionColor
      )
  if state.spans.len > 0 or state.blocks.len > 0:
    sk.drawSpans(state, textOrigin, textColor)
  else:
    discard sk.drawText(
      sk.textStyle,
      editor.displayText,
      textOrigin,
      textColor,
      maxWidth = innerRect.w,
      wordWrap = editor.wordWrap,
      clip = false
    )
  if editor.focused and editor.cursorVisible:
    let cursor = editor.locationRect(editor.cursor)
    sk.drawRect(textOrigin + cursor.xy, cursor.wh, textColor)
  sk.popClipRect()
  sk.drawScrollbars(
    editor, window, outerRect, innerRect, sk.mousePos, sk.clipRect
  )
  if mouseInside and window.scrollDelta.y != 0:
    editor.scrollBy(window.scrollDelta.y * TextBoxScrollSpeed, innerRect.h)
  sk.advance(vec2(boxWidth, boxHeight))

template richTextBox*(
  id: string,
  text: string,
  boxWidth, boxHeight: float32,
  wrapWords = true,
  spans: seq[TextSpan] = default(seq[TextSpan]),
  blocks: seq[TextBlock] = default(seq[TextBlock])
) =
  ## Draws a selectable read-only rich document using the current context.
  sk.richTextBox(
    window,
    id,
    text,
    boxWidth,
    boxHeight,
    wrapWords,
    spans,
    blocks
  )
