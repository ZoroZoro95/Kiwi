import Cocoa
import CoreGraphics

final class CanvasView: NSView {
    
    private var lines : [Line] = []
    private let numCols = 40
    private let numRows = 20
    private var cursor = Cursor(lineIndex: 0, boxIndex: 0)
    private var showGrid = false

    // MARK: - Writing State
    private var currentStroke: [NSPoint] = []
    private var strokeBuffer: [[NSPoint]] = []
    private var dotBuffer: [NSPoint] = []
    
    // MARK: - Symbol Storage
    private var symbols: [Symbol] = []
    
    private var writingEnabled = false

    // MARK: - Timer
    private var bufferTimer: Timer?
    private let commitDelay: TimeInterval = 1.5
    private let mergeWindow: TimeInterval = 2.0

    // MARK: - Drawing
    private let dotRadius: CGFloat = 2.5

    // MARK: - Responder
    override var acceptsFirstResponder: Bool { true }
    
    // MARK: - Cursor Blink
    private var cursorVisible = true
    private var blinkTimer: Timer?
    
    // MARK: - Double Tap
    private var lastTapTime: Date = .distantPast
    private let doubleTapThreshold: TimeInterval = 0.3
    
    // MARK: - Text Space
    private var textCursorIndex: Int = 0
    // MARK: - Grid Setup
    private func setupGrid() {
        lines.removeAll()
        
        let boxWidth = bounds.width / CGFloat(numCols)
        let boxHeight = bounds.height / CGFloat(numRows)
        
        for row in 0..<numRows {
            let y = bounds.height - CGFloat(row + 1) * boxHeight
            var segments: [Segment] = []
            
            for col in 0..<numCols {
                let boxBounds = NSRect(
                    x: CGFloat(col) * boxWidth,
                    y: y,
                    width: boxWidth,
                    height: boxHeight
                )
                let box = GridBox(index: col, symbol: nil, bounds: boxBounds)
                segments.append(.gridBox(box))
            }
            
            let line = Line(segments: segments, y: y)
            lines.append(line)
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
        setupGrid()
        startBlinkTimer()
    }
//    override func layout() {
//        super.layout()
//        setupGrid()
//    }

    deinit {
        NSCursor.unhide()
        CGAssociateMouseAndMouseCursorPosition(1)
    }
    // MARK: - Cursor Movement
    private func moveCursor(deltaCol: Int, deltaRow: Int) {
        var newCol = cursor.boxIndex + deltaCol
        var newRow = cursor.lineIndex + deltaRow

        // if exiting a text space, jump past it entirely
        if cursor.isInTextSpace, let ts = currentTextSpace() {
            if deltaCol > 0 {
                newCol = ts.endCol + 1
                newRow = cursor.lineIndex
            } else if deltaCol < 0 {
                newCol = ts.startCol - 1
                newRow = cursor.lineIndex
            }
        }

        // wrap left
        if newCol < 0 {
            newCol = numCols - 1
            newRow -= 1
        }

        // wrap right
        if newCol >= numCols {
            newCol = 0
            newRow += 1
        }

        // clamp rows
        newRow = max(0, min(newRow, numRows - 1))

        cursor.boxIndex = newCol
        cursor.lineIndex = newRow

        // auto detect if cursor is now in a text space
        let segment = lines[newRow].segments[newCol]
        switch segment {
        case .textSpace(let ts):
            cursor.isInTextSpace = true
            textCursorIndex = deltaCol > 0 ? 0 : ts.content.count
        case .gridBox:
            cursor.isInTextSpace = false
        }

        needsDisplay = true
    }
    // MARK: - Keyboard
    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        let cmd = event.modifierFlags.contains(.command)
        let ctrl = event.modifierFlags.contains(.control)

        // Ctrl+K — toggle drawing
        if ctrl && key == "k" {
            writingEnabled.toggle()
            return
        }

        // Ctrl+G — toggle grid visibility
        if ctrl && key == "g" {
            showGrid.toggle()
            needsDisplay = true
            return
        }

        // Ctrl+T — create text space
        if ctrl && key == "t" {
            createTextSpace()
            return
        }

        // Cmd+Z — undo
        if cmd && key == "z" {
            undoLastSymbol()
            return
        }

        // Cmd+C — clear
        if cmd && key == "c" {
            clearAll()
            return
        }

        // text space mode
        if cursor.isInTextSpace {
            // backspace in text space
            if event.keyCode == 51 {
                handleBackspace()
                return
            }

            // arrow keys — navigate chars, exit at boundary
            if key == String(UnicodeScalar(NSEvent.SpecialKey.leftArrow.rawValue)!) {
                if let ts = currentTextSpace(), textCursorIndex > 0 {
                    textCursorIndex -= 1
                    needsDisplay = true
                } else {
                    moveCursor(deltaCol: -1, deltaRow: 0)
                }
                return
            }
            if key == String(UnicodeScalar(NSEvent.SpecialKey.rightArrow.rawValue)!) {
                if let ts = currentTextSpace(), textCursorIndex < ts.content.count {
                    textCursorIndex += 1
                    needsDisplay = true
                } else {
                    moveCursor(deltaCol: 1, deltaRow: 0)
                }
                return
            }
            if key == String(UnicodeScalar(NSEvent.SpecialKey.upArrow.rawValue)!) {
                moveCursor(deltaCol: 0, deltaRow: -1)
                return
            }
            if key == String(UnicodeScalar(NSEvent.SpecialKey.downArrow.rawValue)!) {
                moveCursor(deltaCol: 0, deltaRow: 1)
                return
            }

            // spacebar
            if event.keyCode == 49 {
                handleTextInput(" ")
                return
            }

            // regular typing
            if let k = event.characters, !k.isEmpty, !ctrl, !cmd {
                handleTextInput(k)
                return
            }

            return
        }

        // grid mode arrow keys
        if key == String(UnicodeScalar(NSEvent.SpecialKey.leftArrow.rawValue)!) {
            moveCursor(deltaCol: -1, deltaRow: 0)
            return
        }
        if key == String(UnicodeScalar(NSEvent.SpecialKey.rightArrow.rawValue)!) {
            moveCursor(deltaCol: 1, deltaRow: 0)
            return
        }
        if key == String(UnicodeScalar(NSEvent.SpecialKey.upArrow.rawValue)!) {
            moveCursor(deltaCol: 0, deltaRow: -1)
            return
        }
        if key == String(UnicodeScalar(NSEvent.SpecialKey.downArrow.rawValue)!) {
            moveCursor(deltaCol: 0, deltaRow: 1)
            return
        }

        // spacebar in grid — force commit
        if event.keyCode == 49 {
            commitBufferedStrokes()
            return
        }
        // grid mode
        // backspace in grid
        if event.keyCode == 51 {
            undoLastSymbol()
            return
        }
        super.keyDown(with: event)
    }
    // MARK: - Touches
    override func touchesBegan(with event: NSEvent) {
        guard writingEnabled else { return }
        currentStroke.removeAll()

        if let touch = event.touches(matching: .touching, in: self).first {
            let n = touch.normalizedPosition
            currentStroke.append(NSPoint(
                x: n.x * bounds.width,
                y: n.y * bounds.height
            ))
        }
    }

    override func touchesMoved(with event: NSEvent) {
        guard writingEnabled else { return }
        guard let touch = event.touches(matching: .touching, in: self).first else { return }

        let n = touch.normalizedPosition
        let point = NSPoint(x: n.x * bounds.width, y: n.y * bounds.height)

        if let last = currentStroke.last {
            if abs(point.x - last.x) < 0.6 &&
               abs(point.y - last.y) < 0.6 { return }
        }

        currentStroke.append(point)
        needsDisplay = true
    }

    override func touchesEnded(with event: NSEvent) {
        guard writingEnabled else { return }

        if currentStroke.count <= 1 {
            if let point = currentStroke.first {
                dotBuffer.append(point)
            }
            currentStroke.removeAll()
            needsDisplay = true
            restartCommitTimer()
            return
        }

        strokeBuffer.append(currentStroke)
        currentStroke.removeAll()
        restartCommitTimer()
    }
    // MARK: - Timer
    private func restartCommitTimer() {
        bufferTimer?.invalidate()
        bufferTimer = Timer.scheduledTimer(
            withTimeInterval: commitDelay,
            repeats: false
        ) { [weak self] _ in
            self?.commitBufferedStrokes()
        }
    }

    private func commitBufferedStrokes() {
        bufferTimer?.invalidate()
        bufferTimer = nil

        guard !strokeBuffer.isEmpty || !dotBuffer.isEmpty else { return }

        let normalizedStrokes = StrokeNormalizer.normalize(strokeBuffer)
        let symbol = buildSymbol(strokes: normalizedStrokes, dots: dotBuffer)
        
        // check grouping with previous symbol
        let prevSymbol = symbols.last
        let grouping = GroupingDetector.detect(current: symbol, previous: prevSymbol)
        
        switch grouping {
        case .newSymbol:
            placeSymbol(symbol)
            
        case .mergeAsDot:
            guard var last = symbols.last else { placeSymbol(symbol); return }
            last.dots += symbol.dots
            last.boundingBox = Symbol.computeBoundingBox(strokes: last.strokes, dots: last.dots)
            symbols.removeLast()
            let prevCol = max(cursor.boxIndex - 1, 0)
            let transformed = transformSymbolToBox(last, line: cursor.lineIndex, col: prevCol)
            symbols.append(transformed)
            updateGrid(symbol: transformed, line: cursor.lineIndex, col: prevCol)
            
        case .mergeAsExponent:
            guard var last = symbols.last else { placeSymbol(symbol); return }
            last.exponents.append(symbol)
            symbols.removeLast()
            let prevCol = max(cursor.boxIndex - 1, 0)
            let transformed = transformSymbolToBox(last, line: cursor.lineIndex, col: prevCol)
            symbols.append(transformed)
            updateGrid(symbol: transformed, line: cursor.lineIndex, col: prevCol)
            
        case .mergeAsSubscript:
            guard var last = symbols.last else { placeSymbol(symbol); return }
            last.subscripts.append(symbol)
            symbols.removeLast()
            let prevCol = max(cursor.boxIndex - 1, 0)
            let transformed = transformSymbolToBox(last, line: cursor.lineIndex, col: prevCol)
            symbols.append(transformed)
            updateGrid(symbol: transformed, line: cursor.lineIndex, col: prevCol)
            
        case .mergeAsCoefficient:
            guard var last = symbols.last else { placeSymbol(symbol); return }
            last.strokes += symbol.strokes
            last.boundingBox = Symbol.computeBoundingBox(strokes: last.strokes, dots: last.dots)
            symbols.removeLast()
            let prevCol = max(cursor.boxIndex - 1, 0)
            let transformed = transformSymbolToBox(last, line: cursor.lineIndex, col: prevCol)
            symbols.append(transformed)
            updateGrid(symbol: transformed, line: cursor.lineIndex, col: prevCol)
        }
        
        strokeBuffer.removeAll()
        dotBuffer.removeAll()
        needsDisplay = true
    }

    private func placeSymbol(_ symbol: Symbol) {
        let transformed = transformSymbolToBox(symbol, line: cursor.lineIndex, col: cursor.boxIndex)
        symbols.append(transformed)
        updateGrid(symbol: transformed, line: cursor.lineIndex, col: cursor.boxIndex)
        moveCursor(deltaCol: 1, deltaRow: 0)
    }

    private func updateGrid(symbol: Symbol, line: Int, col: Int) {
        switch lines[line].segments[col] {
        case .gridBox(var box):
            box.symbol = symbol
            lines[line].segments[col] = .gridBox(box)
        default:
            break
        }
    }

//    private func shouldMergeWithPrevious() -> Bool {
//        guard let last = symbols.last else { return false }
//        let elapsed = Date().timeIntervalSince(last.timestamp)
//        return elapsed < mergeWindow
//    }
    

    // MARK: - Helpers
    private func buildSymbol(strokes: [[NSPoint]], dots: [NSPoint]) -> Symbol {
        return Symbol(strokes: strokes, dots: dots)
    }

    private func transformSymbolToBox(_ symbol: Symbol, line: Int, col: Int) -> Symbol {
        let allPoints = symbol.strokes.flatMap { $0 } + symbol.dots
        guard !allPoints.isEmpty else { return symbol }

        let minX = allPoints.map { $0.x }.min()!
        let minY = allPoints.map { $0.y }.min()!
        let writtenHeight = symbol.boundingBox.height

        let box = boxBounds(line: line, col: col)
        let targetHeight = box.height * 0.7
        let scale = targetHeight / max(writtenHeight, 1)
        let midY = box.midY

        let transformedStrokes = symbol.strokes.map { stroke in
            stroke.map { p in
                NSPoint(
                    x: (p.x - minX) * scale + box.minX + 4,
                    y: (p.y - minY) * scale + midY - targetHeight / 2
                )
            }
        }

        let transformedDots = symbol.dots.map { p in
            NSPoint(
                x: (p.x - minX) * scale + box.minX + 4,
                y: (p.y - minY) * scale + midY - targetHeight / 2
            )
        }

        return Symbol(strokes: transformedStrokes, dots: transformedDots)
    }

    // MARK: - Undo & Clear
    private func undoLastSymbol() {
        let targetCol = max(cursor.boxIndex - 1, 0)
        let targetRow = cursor.lineIndex
        
        switch lines[targetRow].segments[targetCol] {
        case .gridBox(var box):
            box.symbol = nil
            lines[targetRow].segments[targetCol] = .gridBox(box)
            cursor.boxIndex = targetCol
            // also remove from symbols array — remove last matching
            if !symbols.isEmpty {
                symbols.removeLast()
            }
        default:
            break
        }
        needsDisplay = true
    }

    private func clearAll() {
        symbols.removeAll()
        strokeBuffer.removeAll()
        dotBuffer.removeAll()
        currentStroke.removeAll()
        bufferTimer?.invalidate()
        bufferTimer = nil
        cursor = Cursor(lineIndex: 0, boxIndex: 0)
        setupGrid()
        needsDisplay = true
    }

    // MARK: - Draw
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.white.setFill()
        bounds.fill()

        // grid
        if showGrid {
            NSColor.lightGray.withAlphaComponent(0.3).setStroke()
            let gridPath = NSBezierPath()
            gridPath.lineWidth = 0.5

            let boxWidth = bounds.width / CGFloat(numCols)
            let boxHeight = bounds.height / CGFloat(numRows)

            for col in 0...numCols {
                let x = CGFloat(col) * boxWidth
                gridPath.move(to: NSPoint(x: x, y: 0))
                gridPath.line(to: NSPoint(x: x, y: bounds.height))
            }

            for row in 0...numRows {
                let y = CGFloat(row) * boxHeight
                gridPath.move(to: NSPoint(x: 0, y: y))
                gridPath.line(to: NSPoint(x: bounds.width, y: y))
            }

            gridPath.stroke()
        }

        // current box highlight
        let currentBox = boxBounds(line: cursor.lineIndex, col: cursor.boxIndex)
        NSColor.blue.withAlphaComponent(0.1).setFill()
        currentBox.fill()

        // blinking cursor line
        if cursorVisible {
            NSColor.blue.withAlphaComponent(0.8).setStroke()
            let cursorPath = NSBezierPath()
            cursorPath.lineWidth = 2
            let cursorX = currentBox.minX + 3
            let cursorTop = currentBox.maxY - 6
            let cursorBottom = currentBox.minY + 6
            cursorPath.move(to: NSPoint(x: cursorX, y: cursorBottom))
            cursorPath.line(to: NSPoint(x: cursorX, y: cursorTop))
            cursorPath.stroke()
        }

        // symbols
        NSColor.black.setStroke()
        NSColor.black.setFill()
        for symbol in symbols {
            drawSymbol(symbol)
        }
        // text spaces
        for line in lines {
            for segment in line.segments {
                if case .textSpace(let ts) = segment {
                    // cream background
                    NSColor(red: 1.0, green: 0.98, blue: 0.9, alpha: 1.0).setFill()
                    ts.bounds.fill()
                    
                    // border
                    NSColor.orange.withAlphaComponent(0.3).setStroke()
                    let border = NSBezierPath(rect: ts.bounds)
                    border.lineWidth = 1
                    border.stroke()
                    
                    // text
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 14),
                        .foregroundColor: NSColor.black
                    ]
                    let textPoint = NSPoint(x: ts.bounds.minX + 4, y: ts.bounds.minY + (ts.bounds.height - 14) / 2)
                    (ts.content as NSString).draw(at: textPoint, withAttributes: attrs)
                    
                    // text cursor inside text space
                    if cursor.isInTextSpace && cursor.boxIndex >= ts.startCol && cursor.boxIndex <= ts.endCol {
                        let typedSoFar = String(ts.content.prefix(textCursorIndex))
                        let typedWidth = (typedSoFar as NSString).size(withAttributes: attrs).width
                        let cursorX = ts.bounds.minX + 4 + typedWidth
                        
                        if cursorVisible {
                            NSColor.orange.setStroke()
                            let cursorPath = NSBezierPath()
                            cursorPath.lineWidth = 2
                            cursorPath.move(to: NSPoint(x: cursorX, y: ts.bounds.minY + 4))
                            cursorPath.line(to: NSPoint(x: cursorX, y: ts.bounds.maxY - 4))
                            cursorPath.stroke()
                        }
                    }
                }
            }
        }
        // live preview
        let previewPath = NSBezierPath()
        previewPath.lineWidth = 2
        previewPath.lineCapStyle = .round
        previewPath.lineJoinStyle = .round

        for stroke in strokeBuffer {
            guard let first = stroke.first else { continue }
            previewPath.move(to: first)
            for p in stroke.dropFirst() { previewPath.line(to: p) }
        }

        if let first = currentStroke.first {
            previewPath.move(to: first)
            for p in currentStroke.dropFirst() { previewPath.line(to: p) }
        }

        previewPath.stroke()

        // hint
        if !writingEnabled {
            let text = "Press Ctrl + K to start writing"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: NSColor.gray
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(
                    x: (bounds.width - size.width) / 2,
                    y: (bounds.height - size.height) / 2
                ),
                withAttributes: attrs
            )
        }
    }

    // MARK: - Grid Helpers
    private func boxBounds(line: Int, col: Int) -> NSRect {
        let boxWidth = bounds.width / CGFloat(numCols)
        let boxHeight = bounds.height / CGFloat(numRows)
        return NSRect(
            x: CGFloat(col) * boxWidth,
            y: bounds.height - CGFloat(line + 1) * boxHeight,
            width: boxWidth,
            height: boxHeight
        )
    }

    private func drawSymbol(_ symbol: Symbol) {
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for stroke in symbol.strokes {
            guard let first = stroke.first else { continue }
            path.move(to: first)
            for p in stroke.dropFirst() { path.line(to: p) }
        }
        path.stroke()

        for dot in symbol.dots {
            let rect = NSRect(
                x: dot.x - dotRadius,
                y: dot.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            NSBezierPath(ovalIn: rect).fill()
        }
    }
    
    private func startBlinkTimer() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.cursorVisible.toggle()
            self?.needsDisplay = true
        }
    }
    
    private func isDoubleTap() -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTapTime)
        lastTapTime = now
        return elapsed < doubleTapThreshold
    }
    
    // MARK: - Text Space
    private func createTextSpace() {
        // check if cursor is already on a text space — re-enter it
        let segment = lines[cursor.lineIndex].segments[cursor.boxIndex]
        if case .textSpace(let ts) = segment {
            cursor.isInTextSpace = true
            cursor.boxIndex = ts.startCol
            textCursorIndex = ts.content.count
            needsDisplay = true
            return
        }
        
        let boxWidth = bounds.width / CGFloat(numCols)
        let boxHeight = bounds.height / CGFloat(numRows)
        
        // create 1 box ahead of current cursor
        let startCol = min(cursor.boxIndex + 1, numCols - 1)
        let endCol = min(startCol + 2, numCols - 1)
        
        let textSpace = TextSpace(
            startCol: startCol,
            endCol: endCol,
            row: cursor.lineIndex,
            boxWidth: boxWidth,
            boxHeight: boxHeight,
            canvasHeight: bounds.height
        )
        
        for col in startCol...endCol {
            lines[cursor.lineIndex].segments[col] = .textSpace(textSpace)
        }
        
        cursor.isInTextSpace = true
        cursor.boxIndex = startCol
        textCursorIndex = 0
        needsDisplay = true
    }
    private func exitTextSpace() {
        cursor.isInTextSpace = false
        // move cursor to next grid box after text space
        if let ts = currentTextSpace() {
            cursor.boxIndex = min(ts.endCol + 1, numCols - 1)
        }
        needsDisplay = true
    }

    private func currentTextSpace() -> TextSpace? {
        for segment in lines[cursor.lineIndex].segments {
            if case .textSpace(let ts) = segment {
                if cursor.boxIndex >= ts.startCol && cursor.boxIndex <= ts.endCol {
                    return ts
                }
            }
        }
        return nil
    }
    
    private func handleTextInput(_ key: String) {
        guard cursor.isInTextSpace else { return }
        guard var ts = currentTextSpace() else { return }
        
        // safe index calculation
        let safeIndex = min(textCursorIndex, ts.content.count)
        let insertIndex = ts.content.index(ts.content.startIndex, offsetBy: safeIndex)
        ts.content.insert(contentsOf: key, at: insertIndex)
        textCursorIndex = safeIndex + key.count
        
        // update all segments for this text space
        for col in ts.startCol...ts.endCol {
            lines[cursor.lineIndex].segments[col] = .textSpace(ts)
        }
        
        // check if we need to extend or wrap
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
        let textWidth = (ts.content as NSString).size(withAttributes: attrs).width
        let boxWidth = bounds.width / CGFloat(numCols)
        let currentWidth = CGFloat(ts.endCol - ts.startCol + 1) * boxWidth
        
        if textWidth > currentWidth - 10 {
            if ts.endCol < numCols - 1 {
                // extend right
                ts.endCol += 1
                let boxHeight = bounds.height / CGFloat(numRows)
                ts.bounds = NSRect(
                    x: CGFloat(ts.startCol) * boxWidth,
                    y: ts.bounds.minY,
                    width: CGFloat(ts.endCol - ts.startCol + 1) * boxWidth,
                    height: boxHeight
                )
                for col in ts.startCol...ts.endCol {
                    lines[cursor.lineIndex].segments[col] = .textSpace(ts)
                }
            } else {
                // wrap to next line
                wrapTextSpaceToNextLine(ts)
            }
        }
        
        needsDisplay = true
    }

    private func wrapTextSpaceToNextLine(_ currentTs: TextSpace) {
        let nextRow = cursor.lineIndex + 1
        guard nextRow < numRows else { return }
        
        let boxWidth = bounds.width / CGFloat(numCols)
        let boxHeight = bounds.height / CGFloat(numRows)
        
        // create new text space on next line starting at col 0
        var newTs = TextSpace(
            startCol: 0,
            endCol: 2,
            row: nextRow,
            boxWidth: boxWidth,
            boxHeight: boxHeight,
            canvasHeight: bounds.height
        )
        newTs.content = ""
        
        for col in 0...2 {
            lines[nextRow].segments[col] = .textSpace(newTs)
        }
        
        // move cursor to next line
        cursor.lineIndex = nextRow
        cursor.boxIndex = 0
        textCursorIndex = 0
    }

    private func autoExtendTextSpaceIfNeeded(_ textSpace: TextSpace) {
        var ts = textSpace
        let boxWidth = bounds.width / CGFloat(numCols)
        let boxHeight = bounds.height / CGFloat(numRows)
        
        // estimate text width
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14)
        ]
        let textWidth = (ts.content as NSString).size(withAttributes: attrs).width
        let currentWidth = CGFloat(ts.endCol - ts.startCol + 1) * boxWidth
        
        if textWidth > currentWidth - 10 && ts.endCol < numCols - 1 {
            ts.endCol += 1
            ts.bounds = NSRect(
                x: CGFloat(ts.startCol) * boxWidth,
                y: ts.bounds.minY,
                width: CGFloat(ts.endCol - ts.startCol + 1) * boxWidth,
                height: boxHeight
            )
            // add new segment for expanded col
            lines[cursor.lineIndex].segments[ts.endCol] = .textSpace(ts)
            // update all existing segments
            for col in ts.startCol...ts.endCol {
                lines[cursor.lineIndex].segments[col] = .textSpace(ts)
            }
        }
    }
    private func handleBackspace() {
        guard cursor.isInTextSpace else { return }
        guard var ts = currentTextSpace() else { return }
        guard textCursorIndex > 0 && !ts.content.isEmpty else { return }
        
        let safeIndex = min(textCursorIndex, ts.content.count)
        let removeIndex = ts.content.index(ts.content.startIndex, offsetBy: safeIndex - 1)
        ts.content.remove(at: removeIndex)
        textCursorIndex = safeIndex - 1
        
        for col in ts.startCol...ts.endCol {
            lines[cursor.lineIndex].segments[col] = .textSpace(ts)
        }
        needsDisplay = true
    }
}
