import
  std/[algorithm, tables, unicode, times],
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
  MaxRunRunes = 128
  MaxTableColumns = 128

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

  TableAlignment* = enum
    TableLeft, TableCenter, TableRight

  TextCell* = object
    ## One table cell over the document's shared rune offsets.
    first*, last*: int
    alignment*: TableAlignment
    font*: string

  TextBlock* = object
    ## A styled block over a half-open range of shared rune offsets.
    first*, last*: int
    font*: string
    noWrap*: bool
      ## Keeps preformatted rows intact inside an otherwise wrapped document.
    image*: string
    imageTexture*: uint32
      ## Independent texture used instead of an atlas sprite when nonzero.
    imageSize*, imagePixels*: Vec2
      ## Logical image bounds and optional cropped atlas pixel dimensions.
    imagePlaceholderPatch*: string
    imagePlaceholderBorder*: int = 8
      ## Native themed surface shown until an image sprite becomes available.
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
    tableColumns*: int
    tableCells*: seq[TextCell]
    tableHeaderFont*: string
    tableHeaderColor*, tableBorderColor*: ColorRGBX
    tablePadding*: Vec2 = vec2(10.0'f, 8.0'f)
    tableBorderWidth*: float32 = 1

  TableRowLayout = object
    top, bottom: float32

  CellLayout = object
    first, last: int
    bounds: Rect
    top, bottom: float32

  BlockLayout = object
    bounds: Rect
    ruleBounds: Rect
    imageBounds: Rect
    quoteBounds: Rect
    labelBounds: Rect
    labelFont: string
    tableBounds: Rect
    tableColumns: seq[float32]
    tableRows: seq[TableRowLayout]
    tableFirst, tableLast: int
    top, bottom: float32

  TextRun = object
    text: string
    font: string
    position: Vec2
    bounds: Rect
    decorationRight: float32
    clip: Rect
    clipped: bool
    span: int
    top, bottom: float32

  TextLine = object
    first, last: int
    top, bottom: float32

  RichTextBoxState* = ref object
    ## Read-only styled content with one shared plain-text selection state.
    editor*: TextBoxState
    spans*: seq[TextSpan]
    blocks*: seq[TextBlock]
    activatedSpan*: int = -1
    hoveredSpan*: int = -1
    cursorNavigated*: bool
      ## Reports consumed navigation keys during the latest widget draw.
    runeSpans: seq[int]
    runs: seq[TextRun]
    blockLayouts: seq[BlockLayout]
    cellLayouts: seq[CellLayout]
    lines: seq[TextLine]
    contentWidth: float32
    renderMargin: float32
    lastFont: string
    focusEpoch: uint64
    pressedSpan: int = -1
    pressPosition: Vec2
    spanDragged: bool
    when defined(silkyTesting):
      renderedRuns*: int
      renderedBlocks*: int
      renderedSelectionRects*: int
      renderedTableRows*: int

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
  ## Compares cached UTF-8 bytes after native text edits invalidate the cache.
  if state.editor.password:
    state.editor.sameText(text)
  else:
    state.editor.displayText() == text

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

when defined(silkyTesting):
  proc runDecorationBounds*(state: RichTextBoxState): seq[Rect] =
    ## Exposes cached decoration geometry without a native drawing context.
    for run in state.runs:
      result.add(rect(
        run.bounds.xy,
        vec2(run.decorationRight - run.bounds.x, run.bounds.h)
      ))

proc imageBounds*(state: RichTextBoxState, index: int): Rect =
  ## Returns one image's document coordinates for native hit testing.
  if index >= 0 and index < state.blockLayouts.len:
    result = state.blockLayouts[index].imageBounds

proc alignImageBounds*(bounds: Rect, pixelScale: float32): Rect =
  ## Snaps position and size independently so scrolling never resizes pixels.
  let
    scale = max(pixelScale, 0.001'f)
    left = round(bounds.x * scale) / scale
    top = round(bounds.y * scale) / scale
    width = round(bounds.w * scale) / scale
    height = round(bounds.h * scale) / scale
  rect(left, top, max(0.0'f, width), max(0.0'f, height))

proc blockBounds*(state: RichTextBoxState, index: int): Rect =
  ## Returns one block's document coordinates for clipped lazy content.
  if index >= 0 and index < state.blockLayouts.len:
    result = state.blockLayouts[index].bounds

proc tableCellBounds*(
  state: RichTextBoxState,
  blockIndex, cellIndex: int
): Rect =
  ## Returns one table cell's document bounds without exposing layout storage.
  if blockIndex >= 0 and blockIndex < state.blockLayouts.len:
    let
      blockLayout = state.blockLayouts[blockIndex]
      index = blockLayout.tableFirst + cellIndex
    if cellIndex >= 0 and index < blockLayout.tableLast:
      result = state.cellLayouts[index].bounds

proc horizontalScrollbarHeight*(
  state: RichTextBoxState,
  width: float32
): float32 =
  ## Returns the space needed beneath overflowing preformatted content.
  if state.contentWidth <= max(0.0'f, width) + 0.001'f:
    return 0
  if not state.editor.wordWrap:
    return 10
  for item in state.blocks:
    if item.noWrap:
      return 10

proc visibleRange[T](items: openArray[T], top, bottom: float32): Slice[int] =
  ## Finds a bounded interval in cached, vertically ordered layout records.
  var
    first = 0
    last = items.len
  while first < last:
    let middle = (first + last) div 2
    if items[middle].bottom < top:
      first = middle + 1
    else:
      last = middle
  result.a = first
  last = items.len
  while first < last:
    let middle = (first + last) div 2
    if items[middle].top <= bottom:
      first = middle + 1
    else:
      last = middle
  result.b = first - 1

proc cacheGeometry(state: RichTextBoxState) =
  ## Stores width and line ranges once so clipping never scans the document.
  state.contentWidth = 0
  state.lines.setLen(0)
  for i, bounds in state.editor.layout:
    state.contentWidth = max(state.contentWidth, bounds.x + bounds.w)
    if state.lines.len > 0 and state.lines[^1].top == bounds.y and
      i > 0 and state.editor.runes[i - 1] notin [Tab, LF] and
      bounds.x >= state.editor.layout[i - 1].x:
        state.lines[^1].last = i + 1
        state.lines[^1].bottom = max(
          state.lines[^1].bottom, bounds.y + bounds.h
        )
    else:
      state.lines.add(TextLine(
        first: i,
        last: i + 1,
        top: bounds.y,
        bottom: bounds.y + bounds.h
      ))
  var ordered = true
  for i in 1 ..< state.lines.len:
    if state.lines[i].top < state.lines[i - 1].top:
      ordered = false
      break
  if not ordered:
    state.lines.sort(proc(a, b: TextLine): int =
      ## Orders visual fragments while retaining their logical rune ranges.
      result = cmp(a.top, b.top)
      if result == 0:
        result = cmp(a.first, b.first)
    )
  ordered = true
  for i in 1 ..< state.runs.len:
    if state.runs[i].bounds.y < state.runs[i - 1].bounds.y:
      ordered = false
      break
  if not ordered:
    state.runs.sort(proc(a, b: TextRun): int =
      ## Keeps drawing and clipping independent of row-major cell text order.
      result = cmp(a.bounds.y, b.bounds.y)
      if result == 0:
        result = cmp(a.bounds.x, b.bounds.x)
    )
  var bottom = 0.0'f
  for line in state.lines.mitems:
    bottom = max(bottom, line.bottom)
    line.bottom = bottom
  bottom = 0.0'f
  for run in state.runs.mitems:
    run.top = run.bounds.y
    bottom = max(bottom, run.bounds.y + run.bounds.h)
    run.bottom = bottom
  bottom = 0.0'f
  for i, layout in state.blockLayouts.mpairs:
    layout.top = layout.bounds.y
    bottom = max(
      bottom,
      layout.bounds.y + layout.bounds.h + max(0.0'f, state.blocks[i].spacing)
    )
    layout.bottom = bottom

proc cacheRuns(
  state: RichTextBoxState,
  fonts: openArray[FontAtlas],
  names: openArray[string],
  baseline: float32
) =
  ## Splits measured lines into bounded native text draws without reflowing.
  state.runs.setLen(0)
  var i = 0
  while i < state.editor.runes.len:
    if state.editor.runes[i] in [LF, Tab]:
      inc i
      continue
    let
      first = i
      span = state.runeSpans[i]
      font = fonts[span + 1]
      bounds = state.editor.layout[i]
    var text = ""
    while i < state.editor.runes.len and
      i - first < MaxRunRunes and
      state.editor.runes[i] notin [LF, Tab] and
      state.runeSpans[i] == span and state.editor.layout[i].y == bounds.y:
        text.add($state.editor.runes[i])
        inc i
    let
      last = state.editor.layout[i - 1]
      continues = i - first == MaxRunRunes and
        i < state.editor.runes.len and
        state.editor.runes[i] notin [LF, Tab] and
        state.runeSpans[i] == span and
        state.editor.layout[i].y == bounds.y
      decorationRight =
        if continues: state.editor.layout[i].x
        else: last.x + last.w
    state.runs.add(TextRun(
      text: text,
      font: names[span + 1],
      position: vec2(bounds.x, bounds.y + baseline - font.ascent),
      bounds: rect(
        bounds.x, bounds.y, last.x + last.w - bounds.x, bounds.h
      ),
      decorationRight: decorationRight,
      span: state.runeSpans[first]
    ))

proc computeLayout*(
  state: RichTextBoxState,
  fonts: Table[string, FontAtlas],
  baseFont: string,
  maxWidth: float32
)

proc computeTable(
  state: RichTextBoxState,
  item: TextBlock,
  fonts: Table[string, FontAtlas],
  baseFont: string,
  origin: Vec2,
  width: float32
): BlockLayout =
  ## Fits styled cells to shared columns and keeps their logical text order.
  let
    columns = item.tableColumns
    firstBound = clamp(item.first, 0, state.editor.runes.len)
    lastBound = clamp(item.last, firstBound, state.editor.runes.len)
    count = ((item.tableCells.len + columns - 1) div columns) * columns
    paddingY = max(0.0'f, item.tablePadding.y)
    requestedPadding = max(0.0'f, item.tablePadding.x)
  var
    locals = newSeq[RichTextBoxState](count)
    indices = newSeq[seq[int]](count)
    cells = newSeq[TextCell](count)
    preferred = newSeq[float32](columns)
    widths = newSeq[float32](columns)
    covered = firstBound
  for i in 0 ..< count:
    var cell =
      if i < item.tableCells.len: item.tableCells[i]
      else: TextCell(first: item.last, last: item.last)
    cell.first = clamp(cell.first, covered, lastBound)
    cell.last = clamp(cell.last, cell.first, lastBound)
    covered = cell.last
    cells[i] = cell
    locals[i] = RichTextBoxState(
      editor: TextBoxState(
        runes: state.editor.runes[cell.first ..< cell.last],
        wordWrap: false, enabled: false
      ),
      spans: @[TextSpan()]
    )
    indices[i] = @[-1]
  for index, span in state.spans:
    if span.last <= firstBound or span.first >= lastBound:
      continue
    var
      first = 0
      last = cells.len
    while first < last:
      let middle = (first + last) div 2
      if cells[middle].last <= span.first:
        first = middle + 1
      else:
        last = middle
    while first < cells.len and cells[first].first < span.last:
      let cell = cells[first]
      if cell.last > cell.first:
        var relative = span
        relative.first = max(cell.first, span.first) - cell.first
        relative.last = min(cell.last, span.last) - cell.first
        locals[first].spans.add(relative)
        indices[first].add(index)
      inc first
  var total = 0.0'f
  for i, local in locals:
    let
      cell = cells[i]
      font =
        if cell.font in fonts: cell.font
        elif i < columns and item.tableHeaderFont in fonts:
          item.tableHeaderFont
        elif item.font in fonts: item.font
        else: baseFont
      column = i mod columns
    local.computeLayout(fonts, font, float32.high)
    preferred[column] = max(
      preferred[column],
      min(width, max(32.0'f, local.editor.innerWidth + requestedPadding * 2))
    )
  for value in preferred:
    total += value
  if total <= width:
    for i in 0 ..< columns:
      widths[i] = preferred[i] + (width - total) / columns.float32
  else:
    var
      minimum = 0.0'f
      demand = 0.0'f
    for i in 0 ..< columns:
      widths[i] = min(preferred[i], 128.0'f)
      minimum += widths[i]
      demand += preferred[i] - widths[i]
    for i in 0 ..< columns:
      if minimum > width:
        widths[i] *= width / minimum
      elif demand > 0:
        widths[i] += (width - minimum) * (preferred[i] - widths[i]) / demand
  result.tableBounds = rect(origin, vec2(width, 0))
  result.tableFirst = state.cellLayouts.len
  # Keep edge storage fixed while reading previous column positions.
  result.tableColumns = newSeq[float32](columns + 1)
  result.tableColumns[0] = origin.x
  for i, columnWidth in widths:
    result.tableColumns[i + 1] = result.tableColumns[i] + columnWidth
  result.tableColumns[^1] = origin.x + width
  var
    top = origin.y
    previous = rect(origin, vec2(0, state.editor.lineHeight))
    copied = firstBound
  for row in 0 ..< count div columns:
    var height = 0.0'f
    for column in 0 ..< columns:
      let
        i = row * columns + column
        local = locals[i]
        paddingX = min(requestedPadding, widths[column] / 4)
        available = max(0.0'f, widths[column] - paddingX * 2)
        font = local.lastFont
      local.editor.wordWrap = true
      local.computeLayout(fonts, font, available)
      height = max(height, local.innerHeight + paddingY * 2)
    result.tableRows.add(TableRowLayout(top: top, bottom: top + height))
    for column in 0 ..< columns:
      let
        i = row * columns + column
        cell = cells[i]
        local = locals[i]
        paddingX = min(requestedPadding, widths[column] / 4)
        available = max(0.0'f, widths[column] - paddingX * 2)
        cellOrigin = vec2(
          result.tableColumns[column] + paddingX,
          top + paddingY
        )
        bounds = rect(result.tableColumns[column], top, widths[column], height)
      state.cellLayouts.add(CellLayout(
        first: cell.first, last: cell.last, bounds: bounds,
        top: top, bottom: top + height
      ))
      var offsets = newSeq[float32](local.lines.len)
      for lineIndex, line in local.lines:
        var lineWidth = 0.0'f
        for j in line.first ..< line.last:
          let glyph = local.editor.layout[j]
          lineWidth = max(lineWidth, glyph.x + glyph.w)
        let spare = max(0.0'f, available - lineWidth)
        offsets[lineIndex] =
          case cell.alignment
          of TableLeft: 0.0'f
          of TableCenter: spare / 2
          of TableRight: spare
        for j in line.first ..< line.last:
          local.editor.layout[j].x += offsets[lineIndex]
      for j in copied ..< cell.first:
        state.editor.layout[j] = previous
      for j, glyph in local.editor.layout:
        var shifted = rect(cellOrigin + glyph.xy, glyph.wh)
        shifted.x = min(shifted.x, bounds.x + bounds.w)
        shifted.w = min(shifted.w, max(0.0'f, bounds.x + bounds.w - shifted.x))
        state.editor.layout[cell.first + j] = shifted
        let span = local.runeSpans[j]
        if span >= 0:
          state.runeSpans[cell.first + j] = indices[i][span]
      for run in local.runs.mitems:
        var shift = cellOrigin
        var
          firstLine = 0
          lastLine = local.lines.len
        while firstLine < lastLine:
          let middle = (firstLine + lastLine) div 2
          if local.lines[middle].top < run.bounds.y:
            firstLine = middle + 1
          else:
            lastLine = middle
        if firstLine < offsets.len:
          shift.x += offsets[firstLine]
        run.position += shift
        run.bounds.x += shift.x
        run.bounds.y += shift.y
        run.decorationRight += shift.x
        run.clip = bounds
        run.clipped = true
        if run.span >= 0:
          run.span = indices[i][run.span]
        state.runs.add(run)
      previous = rect(cellOrigin, vec2(0, local.editor.lineHeight))
      if local.editor.layout.len > 0:
        let last = state.editor.layout[cell.last - 1]
        previous = rect(last.x + last.w, last.y, 0, last.h)
      # A tab or newline after an empty cell is its selectable caret position.
      if cell.first == cell.last and cell.last < state.editor.layout.len:
        state.editor.layout[cell.last] = previous
      copied = cell.last
      state.renderMargin = max(state.renderMargin, local.renderMargin)
    top += height
  for i in copied ..< lastBound:
    state.editor.layout[i] = previous
  result.tableBounds.h = top - origin.y
  result.tableLast = state.cellLayouts.len
  state.editor.layoutCursor = previous

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
  state.cellLayouts.setLen(0)
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
    if item.tableColumns in 1 .. MaxTableColumns and item.tableCells.len > 0:
      var measured = state.computeTable(
        item, fonts, baseFont,
        vec2(quoteInset + padding.x, state.editor.layoutHeight + padding.y),
        max(0.0'f, blockWidth - padding.x * 2)
      )
      let height = measured.tableBounds.h + padding.y * 2
      measured.bounds = rect(
        quoteInset,
        state.editor.layoutHeight,
        blockWidth,
        height
      )
      measured.quoteBounds = rect(
        padding.x, state.editor.layoutHeight, max(0.0'f, width - padding.x * 2),
        height
      )
      state.blockLayouts.add(move(measured))
      state.editor.layoutHeight += height + max(0.0'f, item.spacing)
      previousEnd = state.editor.layoutCursor
      covered = last
      continue
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
          let label = TextBoxState(wordWrap: true)
          label.setText(item.label)
          label.computeLayout(
            fonts[labelFont], max(0.0'f, blockWidth - padding.x * 2)
          )
          label.innerHeight + max(0.0'f, item.labelSpacing)
        else:
          0.0'f
      imageScale =
        if item.imageSize.x > 0 and item.imageSize.y > 0:
          min(1.0'f, max(0.0'f, blockWidth - padding.x * 2) /
            item.imageSize.x)
        else:
          0.0'f
      imageSize = item.imageSize * imageScale
      imageHeight =
        if imageSize.y > 0:
          imageSize.y + 8
        else:
          0.0'f
      origin = vec2(
        quoteInset + padding.x,
        state.editor.layoutHeight + padding.y + labelHeight + imageHeight
      )
      local = RichTextBoxState(
        editor: TextBoxState(
          runes: state.editor.runes[first ..< last],
          wordWrap: state.editor.wordWrap and not item.noWrap,
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
    state.renderMargin = max(state.renderMargin, local.renderMargin)
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
      run.decorationRight += origin.x
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
    let
      height = contentHeight + padding.y * 2 + labelHeight + imageHeight
      surfaceWidth =
        if item.noWrap:
          max(blockWidth, local.editor.innerWidth + padding.x * 2)
        else:
          blockWidth
    state.blockLayouts.add(BlockLayout(
      bounds: rect(quoteInset, state.editor.layoutHeight, surfaceWidth, height),
      imageBounds: rect(
        quoteInset + padding.x,
        state.editor.layoutHeight + padding.y + labelHeight,
        imageSize.x,
        imageSize.y
      ),
      quoteBounds: rect(
        padding.x, state.editor.layoutHeight, max(0.0'f, width - padding.x * 2),
        height
      ),
      labelBounds: rect(
        quoteInset + padding.x,
        state.editor.layoutHeight + padding.y,
        max(0.0'f, blockWidth - padding.x * 2),
        max(0.0'f, labelHeight - max(0.0'f, item.labelSpacing))
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
  state.renderMargin = fonts[baseFont].lineHeight
  if state.blocks.len > 0:
    state.computeBlocks(fonts, baseFont, maxWidth)
    state.cacheGeometry()
    return
  state.editor.positionedLayout = false
  state.editor.layoutCursor = rect(0, 0, 0, 0)
  state.blockLayouts.setLen(0)
  state.cellLayouts.setLen(0)
  state.editor.layoutHeight = 0
  if state.spans.len == 0:
    state.editor.computeLayout(fonts[baseFont], maxWidth)
    state.runeSpans.setLen(state.editor.runes.len)
    for index in state.runeSpans.mitems:
      index = -1
    state.cacheRuns([fonts[baseFont]], [baseFont], fonts[baseFont].ascent)
    state.cacheGeometry()
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
  state.renderMargin = state.editor.lineHeight
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
  state.cacheRuns(resolvedFonts, fontNames, baseline)
  state.editor.dirty = false
  state.cacheGeometry()

proc spanAt(state: RichTextBoxState, position: Vec2): int =
  ## Finds a formatted span only when the pointer touches its glyph bounds.
  let lines = visibleRange(state.lines, position.y, position.y)
  for line in lines:
    for i in state.lines[line].first ..< state.lines[line].last:
      if position.overlaps(state.editor.layout[i]) and i < state.runeSpans.len:
        return state.runeSpans[i]
  -1

proc drawSpanBackgrounds(sk: Silky, state: RichTextBoxState, origin: Vec2) =
  ## Draws inline backgrounds before the native selection highlight.
  if sk.clipRect.w <= 0 or sk.clipRect.h <= 0:
    return
  let visible = visibleRange(
    state.runs, sk.clipRect.y - origin.y,
    sk.clipRect.y + sk.clipRect.h - origin.y
  )
  for i in visible:
    let
      run = state.runs[i]
      bounds = rect(
        origin + run.bounds.xy,
        vec2(run.decorationRight - run.bounds.x, run.bounds.h)
      )
    if not bounds.overlaps(sk.clipRect):
      continue
    if run.span >= 0:
      let color = state.spans[run.span].background
      if color.a > 0:
        if run.clipped:
          sk.pushClipRect(rect(origin + run.clip.xy, run.clip.wh))
        sk.drawRect(bounds.xy, bounds.wh, color)
        if run.clipped:
          sk.popClipRect()

proc drawTable(
  sk: Silky,
  state: RichTextBoxState,
  item: TextBlock,
  layout: BlockLayout,
  origin: Vec2
) =
  ## Draws only visible row borders with physical-pixel-aligned grid edges.
  if layout.tableRows.len == 0 or layout.tableBounds.w <= 0:
    return
  let
    rows = visibleRange(
      layout.tableRows, sk.clipRect.y - origin.y,
      sk.clipRect.y + sk.clipRect.h - origin.y
    )
    scale = max(sk.uiScale, 0.001'f)
    thickness = max(1.0'f, round(item.tableBorderWidth * scale)) / scale
    left = round((origin.x + layout.tableBounds.x) * scale) / scale
    right = round((origin.x + layout.tableBounds.x + layout.tableBounds.w) *
      scale) / scale
    top = round((origin.y + layout.tableBounds.y) * scale) / scale
    bottom = round((origin.y + layout.tableBounds.y + layout.tableBounds.h) *
      scale) / scale
  if right <= left:
    return
  if rows.a == 0 and item.tableHeaderColor.a > 0:
    let headerBottom = round((origin.y + layout.tableRows[0].bottom) * scale) /
      scale
    sk.drawRect(vec2(left, top), vec2(right - left, headerBottom - top),
      item.tableHeaderColor)
  if item.tableBorderColor.a == 0 or item.tableBorderWidth <= 0:
    return
  for i in rows:
    let y = round((origin.y + layout.tableRows[i].top) * scale) / scale
    sk.drawRect(vec2(left, y), vec2(right - left, thickness),
      item.tableBorderColor)
    when defined(silkyTesting):
      inc state.renderedTableRows
  if bottom >= sk.clipRect.y and bottom <= sk.clipRect.y + sk.clipRect.h:
    sk.drawRect(vec2(left, bottom - thickness), vec2(right - left, thickness),
      item.tableBorderColor)
  let
    visibleTop = max(top, sk.clipRect.y)
    visibleBottom = min(bottom, sk.clipRect.y + sk.clipRect.h)
  if visibleBottom <= visibleTop:
    return
  for i, edge in layout.tableColumns:
    let x =
      if i == layout.tableColumns.high: right - thickness
      else: round((origin.x + edge) * scale) / scale
    sk.drawRect(
      vec2(x, visibleTop),
      vec2(thickness, visibleBottom - visibleTop),
      item.tableBorderColor
    )

proc drawBlocks(
  sk: Silky,
  state: RichTextBoxState,
  origin: Vec2,
  defaultColor: ColorRGBX
) =
  ## Draws native block surfaces, borders, rules, and captions.
  if sk.clipRect.w <= 0 or sk.clipRect.h <= 0:
    return
  let visible = visibleRange(
    state.blockLayouts, sk.clipRect.y - origin.y,
    sk.clipRect.y + sk.clipRect.h - origin.y
  )
  for i in visible:
    let bounds = state.blockLayouts[i]
    when defined(silkyTesting):
      inc state.renderedBlocks
    let item = state.blocks[i]
    if bounds.tableRows.len > 0:
      sk.drawTable(state, item, bounds, origin)
    if item.patch.len > 0:
      sk.draw9Patch(
        item.patch,
        item.patchBorder,
        origin + bounds.bounds.xy,
        bounds.bounds.wh
      )
    if bounds.imageBounds.w > 0 and bounds.imageBounds.h > 0:
      let aligned = alignImageBounds(
        rect(origin + bounds.imageBounds.xy, bounds.imageBounds.wh),
        sk.uiScale
      )
      if item.imageTexture != 0:
        sk.drawTexture(
          item.imageTexture,
          aligned.xy,
          aligned.wh,
          item.imagePixels
        )
      elif item.image in sk.atlas.entries:
        let
          entry = sk.atlas.entries[item.image]
          pixels =
            if item.imagePixels.x > 0 and item.imagePixels.y > 0:
              min(item.imagePixels, vec2(
                entry.width.float32, entry.height.float32
              ))
            else:
              vec2(entry.width.float32, entry.height.float32)
        sk.drawQuad(
          aligned.xy,
          aligned.wh,
          vec2(entry.x.float32, entry.y.float32),
          pixels,
          rgbx(255, 255, 255, 255)
        )
      elif item.imagePlaceholderPatch in sk.atlas.entries:
        sk.draw9Patch(
          item.imagePlaceholderPatch,
          item.imagePlaceholderBorder,
          aligned.xy,
          aligned.wh
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
        origin + bounds.labelBounds.xy,
        color,
        maxWidth = bounds.labelBounds.w,
        maxHeight = bounds.labelBounds.h,
        wordWrap = true
      )

proc drawSpans(
  sk: Silky,
  state: RichTextBoxState,
  origin: Vec2,
  defaultColor: ColorRGBX
) =
  ## Draws cached runs at their measured positions without wrapping again.
  if sk.clipRect.w <= 0 or sk.clipRect.h <= 0:
    return
  let
    margin = state.renderMargin
    visible = visibleRange(
      state.runs, sk.clipRect.y - origin.y - margin,
      sk.clipRect.y + sk.clipRect.h - origin.y + margin
    )
  for i in visible:
    let run = state.runs[i]
    if run.bounds.x + run.bounds.w + origin.x + margin < sk.clipRect.x or
      run.bounds.x + origin.x - margin > sk.clipRect.x + sk.clipRect.w:
        continue
    when defined(silkyTesting):
      inc state.renderedRuns
    let color =
      if run.span >= 0 and state.spans[run.span].color.a > 0:
        state.spans[run.span].color
      else:
        defaultColor
    if run.clipped:
      sk.pushClipRect(rect(origin + run.clip.xy, run.clip.wh))
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
          right = round((origin.x + run.decorationRight) * scale) / scale
          baseline = origin.y + run.position.y + font.ascent
          thickness = max(1.0'f, round(scale)) / scale
        if span.strikethrough:
          let top = round((baseline - font.size * 0.3'f) * scale) / scale
          sk.drawRect(vec2(left, top), vec2(right - left, thickness), color)
        if underline:
          let top = round((baseline + 1) * scale) / scale
          sk.drawRect(vec2(left, top), vec2(right - left, thickness), color)
    if run.clipped:
      sk.popClipRect()

proc drawSelection(
  sk: Silky,
  state: RichTextBoxState,
  origin: Vec2
) =
  ## Draws selected visible lines without walking the offscreen selection.
  if sk.clipRect.w <= 0 or sk.clipRect.h <= 0:
    return
  let
    selection = state.editor.selection
    visible = visibleRange(
      state.lines, sk.clipRect.y - origin.y,
      sk.clipRect.y + sk.clipRect.h - origin.y
    )
  for index in visible:
    let
      line = state.lines[index]
      first = max(selection.a, line.first)
      last = min(selection.b, line.last)
    var rectangles: seq[Rect]
    for i in first ..< last:
      let bounds = state.editor.layout[i]
      if rectangles.len > 0 and rectangles[^1].y == bounds.y and
        rectangles[^1].h == bounds.h and
        bounds.x >= rectangles[^1].x and
        bounds.x - rectangles[^1].x < rectangles[^1].w * 2:
          rectangles[^1].w = bounds.x - rectangles[^1].x + bounds.w
      else:
        rectangles.add(bounds)
    for bounds in rectangles:
      if not rect(origin + bounds.xy, bounds.wh).overlaps(sk.clipRect):
        continue
      sk.drawRect(origin + bounds.xy, bounds.wh, SelectionColor)
      when defined(silkyTesting):
        inc state.renderedSelectionRects

proc mouseAction(
  state: RichTextBoxState,
  position: Vec2,
  click = true,
  shift = false
) =
  ## Keeps empty-cell and short-cell clicks within the intended table column.
  let visible = visibleRange(state.cellLayouts, position.y, position.y)
  for index in visible:
    let cell = state.cellLayouts[index]
    if not position.overlaps(cell.bounds):
      continue
    let editor = state.editor
    var
      cursor = cell.first
      nearestY = float32.high
      nearestX = float32.high
    for i in cell.first ..< cell.last:
      let
        bounds = editor.layout[i]
        distanceY = max(0.0'f,
          max(bounds.y - position.y, position.y - bounds.y - bounds.h))
        distanceX = abs(position.x - bounds.x - bounds.w / 2)
      if distanceY < nearestY or
        (distanceY == nearestY and distanceX < nearestX):
          nearestY = distanceY
          nearestX = distanceX
          cursor = i
          if position.x > bounds.x + bounds.w / 2 and editor.runes[i] != LF:
            inc cursor
    editor.cursor = cursor
    editor.savedX = position.x
    if click and not shift:
      editor.selector = cursor
    editor.scrollToCursor()
    editor.resetBlink()
    return
  state.editor.mouseAction(position, click, shift)

proc selectWord(state: RichTextBoxState, position: Vec2) =
  ## Expands a cell-aware caret through one native whitespace-delimited word.
  state.mouseAction(position)
  let editor = state.editor
  while editor.cursor > 0 and
    not editor.runes[editor.cursor - 1].isWhiteSpace():
      dec editor.cursor
  while editor.selector < editor.runes.len and
    not editor.runes[editor.selector].isWhiteSpace():
      inc editor.selector

proc selectParagraph(state: RichTextBoxState, position: Vec2) =
  ## Selects one logical paragraph or table row from the clicked cell.
  state.mouseAction(position)
  let editor = state.editor
  while editor.cursor > 0 and editor.runes[editor.cursor - 1] != LF:
    dec editor.cursor
  while editor.selector < editor.runes.len and
    editor.runes[editor.selector] != LF:
      inc editor.selector

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
  when defined(silkyTesting):
    state.renderedRuns = 0
    state.renderedBlocks = 0
    state.renderedSelectionRects = 0
    state.renderedTableRows = 0
  editor.enabled = false
  state.activatedSpan = -1
  state.hoveredSpan = -1
  state.cursorNavigated = false
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
  var innerRect = rect(
    sk.at.x + padding,
    sk.at.y + padding,
    boxWidth - padding * 2,
    boxHeight - padding * 2
  )
  if editor.dirty or editor.lastMaxWidth != innerRect.w or
    state.lastFont != sk.textStyle:
      state.computeLayout(sk.atlas.fonts, sk.textStyle, innerRect.w)
  let scrollbarHeight = state.horizontalScrollbarHeight(innerRect.w)
  innerRect.h = max(0.0'f, innerRect.h - scrollbarHeight)
  if abs(innerRect.h - editor.innerHeight) < 0.001'f:
    innerRect.h = editor.innerHeight
  editor.boxSize = innerRect.wh
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
        state.mouseAction(localMouse, click = true, shift = shift)
        editor.dragging = true
        if not shift:
          state.pressedSpan = state.spanAt(localMouse)
          state.pressPosition = mouseVec
          state.spanDragged = false
      of 2:
        state.selectWord(localMouse)
      of 3:
        state.selectParagraph(localMouse)
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
      state.mouseAction(localMouse, click = false, shift = true)
    if window.buttonReleased[MouseLeft] or not window.buttonDown[MouseLeft]:
      editor.dragging = false
  inputs.submitInput(window, "rich-textbox:" & id, editor.focused, false)
  if editor.focused:
    state.focusEpoch = inputs.focusEpoch
    state.cursorNavigated = editor.handleSelectionInput(inputs)
  let maxScrollY = max(0.0'f, editor.innerHeight - innerRect.h)
  editor.scrollPos.y = clamp(editor.scrollPos.y, 0.0'f, maxScrollY)
  let maxScrollX =
    if scrollbarHeight > 0:
      max(0.0'f, state.contentWidth - innerRect.w)
    else:
      0.0'f
  editor.scrollPos.x = clamp(editor.scrollPos.x, 0.0'f, maxScrollX)
  let
    overVerticalBar = editor.innerHeight > innerRect.h and
      mouseVec.x >= outerRect.x + outerRect.w - 10
    overHorizontalBar = scrollbarHeight > 0 and
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
    sk.drawSelection(state, textOrigin)
  sk.drawSpans(state, textOrigin, textColor)
  sk.requestCursorFrame(window, editor, innerRect)
  if editor.focused and editor.cursorVisible:
    let cursor = editor.locationRect(editor.cursor)
    sk.drawRect(textOrigin + cursor.xy, cursor.wh, textColor)
  sk.popClipRect()
  block:
    let wordWrap = editor.wordWrap
    editor.wordWrap = scrollbarHeight == 0
    defer:
      editor.wordWrap = wordWrap
    sk.drawScrollbars(
      editor, window, outerRect, innerRect, sk.mousePos, sk.clipRect,
      measuredWidth = state.contentWidth
    )
  if mouseInside:
    let horizontal =
      if shift and window.scrollDelta.x == 0:
        window.scrollDelta.y
      else:
        window.scrollDelta.x
    if horizontal != 0 and maxScrollX > 0:
      editor.scrollPos.x = clamp(
        editor.scrollPos.x + horizontal * TextBoxScrollSpeed,
        0.0'f,
        maxScrollX
      )
    if not shift and window.scrollDelta.y != 0:
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
