import XCTest
@testable import TrackpadCanvas

final class TrackpadCanvasTests: XCTestCase {
    @MainActor
    func testEraserGestureRestoresMultipleStrokesWithOneUndo() {
        let canvas = ComposerCanvasView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        canvas.trackFinger(at: NSPoint(x: 0.2, y: 0.2), timestamp: 1)
        canvas.trackFinger(at: NSPoint(x: 0.2, y: 0.8), timestamp: 2)
        canvas.setPositioning(true, timestamp: 3)
        canvas.trackFinger(at: NSPoint(x: 0.8, y: 0.2), timestamp: 4)
        canvas.setPositioning(false, timestamp: 5)
        canvas.trackFinger(at: NSPoint(x: 0.8, y: 0.8), timestamp: 6)
        canvas.setPositioning(true, timestamp: 7)
        let original = canvas.document
        canvas.setErasing(true, timestamp: 8)
        canvas.trackFinger(at: NSPoint(x: 0.1, y: 0.5), timestamp: 9)
        XCTAssertEqual(canvas.document, original) // Space suppresses erasing.
        canvas.setPositioning(false, timestamp: 10)
        canvas.trackFinger(at: NSPoint(x: 0.9, y: 0.5), timestamp: 11)
        XCTAssertTrue(canvas.document.isEmpty) // Swept eraser hits both crossing segments.
        canvas.setPositioning(true, timestamp: 12)
        canvas.setErasing(false, timestamp: 13)
        canvas.undo(nil)
        XCTAssertEqual(canvas.document, original)
        canvas.undo(nil)
        XCTAssertEqual(canvas.document.strokes.count, 1)
    }

    @MainActor
    func testUndoRestoresClearAndEmptyEraseDoesNotConsumeHistory() {
        let canvas = ComposerCanvasView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        canvas.trackFinger(at: NSPoint(x: 0.2, y: 0.2), timestamp: 1)
        canvas.setPositioning(true, timestamp: 2)
        let original = canvas.document
        canvas.clear()
        canvas.undo(nil)
        XCTAssertEqual(canvas.document, original)
        canvas.trackFinger(at: NSPoint(x: 0.9, y: 0.9), timestamp: 3)
        canvas.setErasing(true, timestamp: 4)
        canvas.setPositioning(false, timestamp: 5)
        canvas.undo(nil)
        XCTAssertTrue(canvas.document.isEmpty)
        canvas.undo(nil)
        XCTAssertTrue(canvas.document.isEmpty)
    }

    @MainActor
    func testSpacePositioningSplitsStrokesWithoutConnectingLine() {
        let canvas = ComposerCanvasView()
        canvas.trackFinger(at: NSPoint(x: 0.1, y: 0.2), timestamp: 1)
        canvas.trackFinger(at: NSPoint(x: 0.2, y: 0.2), timestamp: 2)
        canvas.setPositioning(true, timestamp: 3)
        canvas.trackFinger(at: NSPoint(x: 0.8, y: 0.8), timestamp: 4)
        canvas.setPositioning(true, timestamp: 5) // Keyboard auto-repeat.
        XCTAssertEqual(canvas.document.strokes.count, 1)
        canvas.setPositioning(false, timestamp: 6)
        canvas.trackFinger(at: NSPoint(x: 0.9, y: 0.8), timestamp: 7)
        canvas.setPositioning(true, timestamp: 8)
        XCTAssertEqual(canvas.document.strokes.count, 2)
        XCTAssertEqual(canvas.document.strokes[0].points.map(\.x), [0.1, 0.2])
        XCTAssertEqual(canvas.document.strokes[1].points.map(\.x), [0.8, 0.9])
    }

    @MainActor
    func testPositioningBeforeTouchDoesNotLeaveInk() {
        let canvas = ComposerCanvasView()
        canvas.setPositioning(true, timestamp: 1)
        canvas.trackFinger(at: NSPoint(x: 0.2, y: 0.5), timestamp: 2)
        canvas.trackFinger(at: NSPoint(x: 0.7, y: 0.5), timestamp: 3)
        XCTAssertTrue(canvas.document.isEmpty)
        canvas.clear()
        canvas.setPositioning(false, timestamp: 4)
        canvas.setPositioning(true, timestamp: 5)
        XCTAssertTrue(canvas.document.isEmpty)
    }

    func testRateLimitDetailsIncludeRetryTimeAndRedactKey() throws {
        let data = Data(#"{"error":{"message":"Daily token limit reached for test-secret"}}"#.utf8)
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://api.groq.com")!,
            statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "61"]))
        let message = GroqRecognitionService.rateLimitMessage(data: data, response: response, key: "test-secret")
        XCTAssertTrue(message.contains("Daily token limit"))
        XCTAssertTrue(message.contains("61 seconds"))
        XCTAssertFalse(message.contains("test-secret"))
    }

    @MainActor
    func testCorrectedLatexIsCopiedAndBlankCannotBeCopied() async throws {
        let session = ComposerSession()
        session.updateDocument(InkDocument(strokes: [InkStroke(points: [try point(0.2, 0.8)])]))
        await session.recognize(using: StubRecognitionService())
        session.editLatex("x^{2}+5x=15")
        let clipboard = RecordingClipboard()
        XCTAssertTrue(session.copy(using: clipboard))
        XCTAssertEqual(clipboard.value, "x^{2}+5x=15")
        session.editLatex(" ")
        XCTAssertFalse(session.canCopy)
        XCTAssertFalse(session.copy(using: clipboard))
    }

    func testGroqSendsPNGAndParsesLatex() async throws {
        let document = InkDocument(strokes: [InkStroke(points: [try point(0.2, 0.8), try point(0.6, 0.3)])])
        let service = GroqRecognitionService(keyProvider: { "test-key" }, transport: { request in
            XCTAssertEqual(request.url?.host, "api.groq.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 512)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            let image = try XCTUnwrap(content.last?["image_url"] as? [String: String])
            let base64 = try XCTUnwrap(image["url"]?.split(separator: ",").last)
            let png = try XCTUnwrap(Data(base64Encoded: String(base64)))
            XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            let data = Data(#"{"choices":[{"message":{"content":"{\"latex\":\"x^2+1\"}"},"finish_reason":"stop"}]}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await service.recognize(document)
        XCTAssertEqual(result.latex, "x^2+1")
    }

    func testGroqMissingKeyDoesNotSendRequest() async throws {
        let service = GroqRecognitionService(keyProvider: { " " }, transport: { _ in
            XCTFail("Missing credentials must not send ink")
            throw URLError(.badURL)
        })
        do {
            _ = try await service.recognize(InkDocument(strokes: [InkStroke(points: [try point(0.2, 0.8)])]))
            XCTFail("Expected missing-key error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("API key"))
        }
    }

    func testGroqRateLimitPreservesActionableError() async throws {
        let service = GroqRecognitionService(keyProvider: { "test-key" }, transport: { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await service.recognize(InkDocument(strokes: [InkStroke(points: [try point(0.2, 0.8)])]))
            XCTFail("Expected rate-limit error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("usage limit"))
        }
    }

    func testGroqRejectsTruncatedAndMalformedResponses() {
        XCTAssertThrowsError(try GroqRecognitionService.decode(Data(#"{"choices":[{"message":{"content":"{\"latex\":\"x\"}"},"finish_reason":"length"}]}"#.utf8)))
        XCTAssertThrowsError(try GroqRecognitionService.decode(Data("not JSON".utf8)))
    }

    @MainActor
    func testEditingDuringRecognitionDiscardsStaleResult() async throws {
        let session = ComposerSession()
        session.updateDocument(InkDocument(strokes: [InkStroke(points: [try point(0.2, 0.8)])]))
        await session.recognize(using: EditingRecognitionService(edit: { session.updateDocument(InkDocument()) }))
        XCTAssertEqual(session.state, .empty)
        XCTAssertFalse(session.canCopy)
    }

    func testPointClampsFiniteCoordinatesAndPressure() throws {
        let point = try XCTUnwrap(InkPoint(x: -0.25, y: 1.4, pressure: 1.5))

        XCTAssertEqual(point.x, 0)
        XCTAssertEqual(point.y, 1)
        XCTAssertEqual(point.pressure, 1)
    }

    func testPointRejectsNonFiniteValues() {
        XCTAssertNil(InkPoint(x: .nan, y: 0.5))
        XCTAssertNil(InkPoint(x: 0.5, y: .infinity))
        XCTAssertNil(InkPoint(x: 0.5, y: 0.5, pressure: -.infinity))
    }

    func testAppendPreservesStrokeOrderAndRejectsEmptyStroke() throws {
        let first = InkStroke(id: UUID(), points: [try point(0.1, 0.1)])
        let second = InkStroke(id: UUID(), points: [try point(0.2, 0.2)])
        var document = InkDocument()

        XCTAssertTrue(document.append(first))
        XCTAssertFalse(document.append(InkStroke(points: [])))
        XCTAssertTrue(document.append(second))
        XCTAssertEqual(document.strokes, [first, second])
    }

    func testUndoRemovesOnlyTheLastStrokeAndIsSafeWhenEmpty() throws {
        let first = InkStroke(id: UUID(), points: [try point(0.1, 0.1)])
        let second = InkStroke(id: UUID(), points: [try point(0.2, 0.2)])
        var document = InkDocument(strokes: [first, second])

        XCTAssertEqual(document.undoLastStroke(), second)
        XCTAssertEqual(document.strokes, [first])
        XCTAssertEqual(document.undoLastStroke(), first)
        XCTAssertNil(document.undoLastStroke())
    }

    func testClearEmptiesTheDocument() throws {
        var document = InkDocument(strokes: [
            InkStroke(points: [try point(0.1, 0.1)])
        ])

        document.clear()

        XCTAssertTrue(document.isEmpty)
    }

    func testEraseRemovesOnlyIntersectingStrokes() throws {
        let inside = InkStroke(id: UUID(), points: [try point(0.5, 0.5)])
        let outside = InkStroke(id: UUID(), points: [try point(0.9, 0.9)])
        var document = InkDocument(strokes: [inside, outside])
        let eraser = try rectangle(0.4, 0.4, 0.6, 0.6)

        let erased = document.eraseStrokes(intersecting: eraser)

        XCTAssertEqual(erased, [inside])
        XCTAssertEqual(document.strokes, [outside])
    }

    func testEraseDetectsSegmentCrossingRectangleWithoutPointInside() throws {
        let crossingStroke = InkStroke(points: [
            try point(0.1, 0.5),
            try point(0.9, 0.5)
        ])
        var document = InkDocument(strokes: [crossingStroke])
        let eraser = try rectangle(0.4, 0.4, 0.6, 0.6)

        XCTAssertEqual(document.eraseStrokes(intersecting: eraser), [crossingStroke])
        XCTAssertTrue(document.isEmpty)
    }

    func testEraseIncludesBoundaryContact() throws {
        let boundaryStroke = InkStroke(points: [try point(0.4, 0.5)])
        var document = InkDocument(strokes: [boundaryStroke])
        let eraser = try rectangle(0.4, 0.4, 0.6, 0.6)

        XCTAssertEqual(document.eraseStrokes(intersecting: eraser), [boundaryStroke])
    }

    func testDocumentCodableRoundTripPreservesInk() throws {
        let document = InkDocument(strokes: [
            InkStroke(
                id: UUID(),
                points: [
                    try point(0.1, 0.2, timestamp: 1, pressure: 0.3),
                    try point(0.4, 0.5, timestamp: 2, pressure: 0.6)
                ]
            )
        ])

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(InkDocument.self, from: encoded)

        XCTAssertEqual(decoded, document)
    }

    func testDraftCodableRoundTripPreservesRecognizedEquation() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let document = InkDocument(strokes: [
            InkStroke(points: [try point(0.25, 0.75)])
        ])
        let draft = EquationDraft(
            id: UUID(),
            document: document,
            recognizedLaTeX: "x^2 + 1",
            createdAt: date,
            updatedAt: date
        )

        let encoded = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(EquationDraft.self, from: encoded)

        XCTAssertEqual(decoded, draft)
    }

    @MainActor
    func testComposerSessionStartsEmptyAndCannotRecognizeOrCopy() {
        let session = ComposerSession()

        XCTAssertEqual(session.state, .empty)
        XCTAssertFalse(session.canRecognize)
        XCTAssertFalse(session.canCopy)
        XCTAssertFalse(session.copy(using: RecordingClipboard()))
    }

    @MainActor
    func testComposerSessionRecognizesInkAndCopiesLatex() async throws {
        let session = ComposerSession()
        let document = InkDocument(strokes: [
            InkStroke(points: [try point(0.25, 0.75)])
        ])
        let clipboard = RecordingClipboard()

        session.updateDocument(document)
        await session.recognize(using: StubRecognitionService())

        XCTAssertEqual(session.state, .recognized(RecognitionResult(latex: "x^2 + 1")))
        XCTAssertTrue(session.canCopy)
        XCTAssertTrue(session.copy(using: clipboard))
        XCTAssertEqual(clipboard.value, "x^2 + 1")
    }

    @MainActor
    func testComposerSessionEditingInvalidatesRecognizedResult() async throws {
        let session = ComposerSession()
        var document = InkDocument(strokes: [
            InkStroke(points: [try point(0.25, 0.75)])
        ])
        session.updateDocument(document)
        await session.recognize(using: StubRecognitionService())

        document.append(InkStroke(points: [try point(0.5, 0.5)]))
        session.updateDocument(document)

        XCTAssertEqual(session.state, .drawing)
        XCTAssertFalse(session.canCopy)
    }

    @MainActor
    func testComposerSessionExposesRecognitionFailureWithoutDeletingInk() async throws {
        let session = ComposerSession()
        let document = InkDocument(strokes: [
            InkStroke(points: [try point(0.25, 0.75)])
        ])
        session.updateDocument(document)

        await session.recognize(using: FailingRecognitionService())

        XCTAssertEqual(session.state, .failed("Recognition unavailable"))
        XCTAssertEqual(session.document, document)
        XCTAssertTrue(session.canRecognize)
    }

    @MainActor
    func testComposerSessionRejectsWhitespaceOnlyRecognitionResult() async throws {
        let session = ComposerSession()
        session.updateDocument(InkDocument(strokes: [
            InkStroke(points: [try point(0.25, 0.75)])
        ]))

        await session.recognize(using: EmptyRecognitionService())

        XCTAssertEqual(session.state, .failed("Recognition returned an empty equation."))
        XCTAssertFalse(session.canCopy)
    }

    private func point(
        _ x: Double,
        _ y: Double,
        timestamp: TimeInterval = 0,
        pressure: Double? = nil
    ) throws -> InkPoint {
        try XCTUnwrap(
            InkPoint(x: x, y: y, timestamp: timestamp, pressure: pressure)
        )
    }

    private func rectangle(
        _ x1: Double,
        _ y1: Double,
        _ x2: Double,
        _ y2: Double
    ) throws -> NormalizedRect {
        try XCTUnwrap(NormalizedRect(x1: x1, y1: y1, x2: x2, y2: y2))
    }
}

private final class RecordingClipboard: ClipboardWriting {
    private(set) var value: String?

    func write(_ string: String) -> Bool {
        value = string
        return true
    }
}

private struct FailingRecognitionService: RecognitionService {
    struct TestError: LocalizedError {
        var errorDescription: String? { "Recognition unavailable" }
    }

    func recognize(_ document: InkDocument) async throws -> RecognitionResult {
        throw TestError()
    }
}

private struct EmptyRecognitionService: RecognitionService {
    func recognize(_ document: InkDocument) async throws -> RecognitionResult {
        RecognitionResult(latex: "   ")
    }
}

private struct EditingRecognitionService: RecognitionService {
    let edit: @MainActor () -> Void
    func recognize(_ document: InkDocument) async throws -> RecognitionResult {
        await edit()
        return RecognitionResult(latex: "stale")
    }
}
