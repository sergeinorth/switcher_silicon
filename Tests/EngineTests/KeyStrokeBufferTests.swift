import XCTest
@testable import Engine

final class KeyStrokeBufferTests: XCTestCase {
    func testAppend() {
        var buffer = KeyStrokeBuffer()
        buffer.append(KeyStroke(characters: "g", keyCode: 5))
        buffer.append(KeyStroke(characters: "h", keyCode: 4))
        XCTAssertEqual(buffer.stringValue, "gh")
    }

    func testBackspace() {
        var buffer = KeyStrokeBuffer()
        buffer.append(KeyStroke(characters: "a", keyCode: 0))
        buffer.append(KeyStroke(characters: "b", keyCode: 11))
        buffer.deleteBackward()
        XCTAssertEqual(buffer.stringValue, "a")
    }

    func testMaxLength() {
        var buffer = KeyStrokeBuffer()
        for i in 0..<40 {
            buffer.append(KeyStroke(characters: "x", keyCode: UInt16(i)))
        }
        XCTAssertEqual(buffer.count, KeyStrokeBuffer.maxLength)
    }
}
