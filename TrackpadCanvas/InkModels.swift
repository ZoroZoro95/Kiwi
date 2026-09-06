import Foundation

struct InkPoint: Codable, Equatable {
    let x: Double
    let y: Double
    let timestamp: TimeInterval
    let pressure: Double?

    init?(
        x: Double,
        y: Double,
        timestamp: TimeInterval = 0,
        pressure: Double? = nil
    ) {
        guard x.isFinite, y.isFinite, timestamp.isFinite else { return nil }
        if let pressure, !pressure.isFinite { return nil }

        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
        self.timestamp = timestamp
        self.pressure = pressure.map(Self.clamp)
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case timestamp
        case pressure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        let pressure = try container.decodeIfPresent(Double.self, forKey: .pressure)

        guard let point = InkPoint(
            x: x,
            y: y,
            timestamp: timestamp,
            pressure: pressure
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .x,
                in: container,
                debugDescription: "Ink point values must be finite."
            )
        }

        self = point
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct InkStroke: Codable, Equatable, Identifiable {
    let id: UUID
    var points: [InkPoint]

    init(id: UUID = UUID(), points: [InkPoint]) {
        self.id = id
        self.points = points
    }

    var isEmpty: Bool { points.isEmpty }
}

struct NormalizedRect: Equatable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    init?(x1: Double, y1: Double, x2: Double, y2: Double) {
        guard x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite else {
            return nil
        }

        minX = Self.clamp(min(x1, x2))
        minY = Self.clamp(min(y1, y2))
        maxX = Self.clamp(max(x1, x2))
        maxY = Self.clamp(max(y1, y2))
    }

    func intersects(_ stroke: InkStroke) -> Bool {
        guard let firstPoint = stroke.points.first else { return false }
        if contains(firstPoint) { return true }

        for (start, end) in zip(stroke.points, stroke.points.dropFirst()) {
            if contains(end) || intersectsSegment(from: start, to: end) {
                return true
            }
        }

        return false
    }

    private func contains(_ point: InkPoint) -> Bool {
        point.x >= minX && point.x <= maxX &&
            point.y >= minY && point.y <= maxY
    }

    private func intersectsSegment(from start: InkPoint, to end: InkPoint) -> Bool {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let boundaries = [
            (-deltaX, start.x - minX),
            (deltaX, maxX - start.x),
            (-deltaY, start.y - minY),
            (deltaY, maxY - start.y)
        ]

        var entry = 0.0
        var exit = 1.0

        for (direction, distance) in boundaries {
            if direction == 0 {
                if distance < 0 { return false }
                continue
            }

            let ratio = distance / direction
            if direction < 0 {
                entry = max(entry, ratio)
            } else {
                exit = min(exit, ratio)
            }

            if entry > exit { return false }
        }

        return true
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct InkDocument: Codable, Equatable {
    private(set) var strokes: [InkStroke]

    init(strokes: [InkStroke] = []) {
        self.strokes = strokes.filter { !$0.isEmpty }
    }

    @discardableResult
    mutating func append(_ stroke: InkStroke) -> Bool {
        guard !stroke.isEmpty else { return false }
        strokes.append(stroke)
        return true
    }

    @discardableResult
    mutating func undoLastStroke() -> InkStroke? {
        strokes.popLast()
    }

    @discardableResult
    mutating func eraseStrokes(intersecting rect: NormalizedRect) -> [InkStroke] {
        let erased = strokes.filter(rect.intersects)
        strokes.removeAll(where: rect.intersects)
        return erased
    }

    mutating func clear() {
        strokes.removeAll()
    }

    var isEmpty: Bool { strokes.isEmpty }
}

struct EquationDraft: Codable, Equatable, Identifiable {
    let id: UUID
    var document: InkDocument
    var recognizedLaTeX: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        document: InkDocument = InkDocument(),
        recognizedLaTeX: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.document = document
        self.recognizedLaTeX = recognizedLaTeX
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
