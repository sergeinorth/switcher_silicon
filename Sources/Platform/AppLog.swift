import Foundation

public enum AppLog {
    private static let path: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SwitcherSilicon.log")
    }()

    private static let queue = DispatchQueue(label: "com.sergei.SwitcherSilicon.log", qos: .utility)
    // Isolated to `queue` — never touch from the event-tap thread.
    nonisolated(unsafe) private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func line(_ message: String) {
        let now = Date()
        queue.async {
            let row = "[\(stampFormatter.string(from: now))] \(message)\n"
            guard let data = row.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: path.path) {
                if let handle = try? FileHandle(forWritingTo: path) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: path)
            }
        }
    }
}
