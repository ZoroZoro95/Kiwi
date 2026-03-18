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

struct TextSpace {
    let id: UUID
    var content: String
    var bounds: NSRect
    var startCol: Int
    var endCol: Int
    var rows: Int
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
