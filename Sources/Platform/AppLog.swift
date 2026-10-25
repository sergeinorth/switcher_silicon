import Foundation

public enum AppLog {
    private static let path: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SwitcherSilicon.log")
    }()

    private static let queue = DispatchQueue(label: "com.sergei.SwitcherSilicon.log", qos: .utility)

    public static func line(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let row = "[\(stamp)] \(message)\n"
        queue.async {
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
