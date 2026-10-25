import Foundation

public struct KeyStroke: Equatable, Sendable {
    public var characters: String
    public var keyCode: UInt16
    public var isFromCurrentLayout: Bool

    public init(characters: String, keyCode: UInt16, isFromCurrentLayout: Bool = true) {
        self.characters = characters
        self.keyCode = keyCode
        self.isFromCurrentLayout = isFromCurrentLayout
    }
}

public struct KeyStrokeBuffer: Equatable, Sendable {
    public static let maxLength = 32

    private(set) public var strokes: [KeyStroke]

    public init(strokes: [KeyStroke] = []) {
        self.strokes = strokes
    }

    public var stringValue: String {
        strokes.map(\.characters).joined()
    }

    public var count: Int { strokes.count }
    public var isEmpty: Bool { strokes.isEmpty }

    public mutating func append(_ stroke: KeyStroke) {
        strokes.append(stroke)
        if strokes.count > Self.maxLength {
            strokes.removeFirst(strokes.count - Self.maxLength)
        }
    }

    public mutating func deleteBackward() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }

    public mutating func clear() {
        strokes.removeAll(keepingCapacity: true)
    }
}
