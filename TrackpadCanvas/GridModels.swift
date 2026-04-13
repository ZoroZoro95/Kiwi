import Foundation
import CoreGraphics

struct GridBox {
    let index: Int
    var symbol: Symbol?
    var isEmpty: Bool { symbol == nil }
    var bounds: NSRect
}

enum Segment {
    case gridBox(GridBox)
    case textSpace(TextSpace)
}


struct Line {
    var segments: [Segment]
    let y: CGFloat
}

struct Cursor {
    var lineIndex: Int
    var boxIndex: Int
    var isInTextSpace: Bool = false
}

struct TextSpace {
    let id: UUID
    var content: String
    var bounds: NSRect
    var startCol: Int
    var endCol: Int
    var rows: Int
    
    init(startCol: Int, endCol: Int, row: Int, boxWidth: CGFloat, boxHeight: CGFloat, canvasHeight: CGFloat) {
        self.id = UUID()
        self.content = ""
        self.startCol = startCol
        self.endCol = endCol
        self.rows = 1
        self.bounds = NSRect(
            x: CGFloat(startCol) * boxWidth,
            y: canvasHeight - CGFloat(row + 1) * boxHeight,
            width: CGFloat(endCol - startCol + 1) * boxWidth,
            height: boxHeight
        )
    }
}
