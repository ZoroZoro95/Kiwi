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
        needsDisplay = true
    }
    // MARK: - Keyboard
    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        let cmd = event.modifierFlags.contains(.command)
        let ctrl = event.modifierFlags.contains(.control)

        if ctrl && key == "k" {
            writingEnabled.toggle()
            return
        }
        
        if ctrl && key == "g" {
            showGrid.toggle()
            needsDisplay = true
            return
        }
        if cmd && key == "z" {
            undoLastSymbol()
            return
        }

        if cmd && key == "c" {
            clearAll()
            return
        }
        // Arrow keys
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
            // it's a dot — buffer it, don't commit yet
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

    // MARK: - Commit
    private func commitBufferedStrokes() {
        bufferTimer?.invalidate()
        bufferTimer = nil

        guard !strokeBuffer.isEmpty || !dotBuffer.isEmpty else { return }

        if shouldMergeWithPrevious() {
            mergeIntoPreviousSymbol()
            return
        }

        let symbol = buildSymbol(strokes: strokeBuffer, dots: dotBuffer)
        let transformed = transformSymbolToBox(symbol, line: cursor.lineIndex, col: cursor.boxIndex)

        // store in grid
        switch lines[cursor.lineIndex].segments[cursor.boxIndex] {
        case .gridBox(var box):
            box.symbol = transformed
            lines[cursor.lineIndex].segments[cursor.boxIndex] = .gridBox(box)
        default:
            break
        }

        symbols.append(transformed)
        cursor.boxIndex = min(cursor.boxIndex + 1, numCols - 1)
        strokeBuffer.removeAll()
        dotBuffer.removeAll()
        needsDisplay = true
    }

    private func shouldMergeWithPrevious() -> Bool {
        guard let last = symbols.last else { return false }
        let elapsed = Date().timeIntervalSince(last.timestamp)
        return elapsed < mergeWindow
    }

    private func mergeIntoPreviousSymbol() {
        guard var last = symbols.last else { return }

        last.strokes += strokeBuffer
        last.dots += dotBuffer
        last.boundingBox = Symbol.computeBoundingBox(
            strokes: last.strokes,
            dots: last.dots
        )

        symbols.removeLast()

        let prevCol = max(cursor.boxIndex - 1, 0)
        let transformed = transformSymbolToBox(last, line: cursor.lineIndex, col: prevCol)
        symbols.append(transformed)

        // update grid
        switch lines[cursor.lineIndex].segments[prevCol] {
        case .gridBox(var box):
            box.symbol = transformed
            lines[cursor.lineIndex].segments[prevCol] = .gridBox(box)
        default:
            break
        }

        strokeBuffer.removeAll()
        dotBuffer.removeAll()
        needsDisplay = true
    }

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
        guard !symbols.isEmpty else { return }
        symbols.removeLast()

        // clear from grid
        let prevCol = max(cursor.boxIndex - 1, 0)
        switch lines[cursor.lineIndex].segments[prevCol] {
        case .gridBox(var box):
            box.symbol = nil
            lines[cursor.lineIndex].segments[prevCol] = .gridBox(box)
        default:
            break
        }

        cursor.boxIndex = prevCol
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
}
