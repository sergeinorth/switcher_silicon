import Foundation
import zlib

/// Open-source word lists shipped as gzipped UTF-8 (one lowercase word per line).
///
/// Sources (see `Resources/Dictionaries/NOTICE.md`):
/// - Russian full forms: danakt/russian-words (MIT) + hingston lists
/// - Russian frequency subset (spell accept): hingston Leeds corpus lists
/// - English: dwyl/english-words (Unlicense)
public enum BundledDictionary: Sendable {
    /// Full morphological RU list — “is this already a real word?”.
    public static let sharedRussian: Set<String> = load(resource: "ru_words")
        .union(SeedDictionary.russian)

    /// High-frequency RU lemmas/forms — only these are accepted as spell *fixes*.
    public static let spellAcceptRussian: Set<String> = load(resource: "ru_freq")
        .union(SeedDictionary.russian)

    public static let sharedEnglish: Set<String> = load(resource: "en_words")
        .union(SeedDictionary.english)

    /// English spell accept = full EN list (Apple/dwyl are reliable enough).
    public static var spellAcceptEnglish: Set<String> { sharedEnglish }

    public static var russianCount: Int { sharedRussian.count }
    public static var englishCount: Int { sharedEnglish.count }
    public static var spellAcceptRussianCount: Int { spellAcceptRussian.count }

    public static func isSpellAcceptable(_ word: String) -> Bool {
        let lower = word.lowercased()
        switch ConversionEngine.dominantScript(lower) {
        case .cyrillic:
            return spellAcceptRussian.contains(lower)
        case .latin:
            return spellAcceptEnglish.contains(lower)
        case .mixed, .other:
            return spellAcceptRussian.contains(lower) || spellAcceptEnglish.contains(lower)
        }
    }

    private static func load(resource: String) -> Set<String> {
        // Prefer packaged .app Resources, then SwiftPM Bundle.module (swift run / tests).
        // Important: only keep URLs that exist — appendingPathComponent always returns a URL.
        let candidates: [URL?] = [
            Bundle.main.url(forResource: resource, withExtension: "txt.gz", subdirectory: "Dictionaries"),
            Bundle.main.resourceURL?.appendingPathComponent("Dictionaries/\(resource).txt.gz"),
            Bundle.module.url(forResource: resource, withExtension: "txt.gz", subdirectory: "Dictionaries"),
            Bundle.module.url(forResource: resource, withExtension: "txt.gz"),
            Bundle.main.url(forResource: resource, withExtension: "txt", subdirectory: "Dictionaries"),
            Bundle.module.url(forResource: resource, withExtension: "txt", subdirectory: "Dictionaries"),
        ]
        guard let url = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return []
        }
        do {
            let fileData = try Data(contentsOf: url)
            let textData: Data
            if url.pathExtension == "gz" || url.lastPathComponent.hasSuffix(".txt.gz") {
                textData = try gunzip(fileData)
            } else {
                textData = fileData
            }
            guard let text = String(data: textData, encoding: .utf8) else { return [] }
            var set = Set<String>()
            set.reserveCapacity(max(text.count / 10, 1024))
            text.enumerateLines { line, _ in
                if !line.isEmpty {
                    set.insert(line)
                }
            }
            return set
        } catch {
            return []
        }
    }

    private static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        var status = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int32 in
            guard let base = src.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(src.count)
            return inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard status == Z_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { inflateEnd(&stream) }

        let chunk = 256 * 1024
        var output = Data()
        repeat {
            var buffer = [UInt8](repeating: 0, count: chunk)
            status = buffer.withUnsafeMutableBytes { dst in
                stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(chunk)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let produced = chunk - Int(stream.avail_out)
            if produced > 0 {
                output.append(contentsOf: buffer.prefix(produced))
            }
            if status == Z_STREAM_END { break }
            if status != Z_OK { throw CocoaError(.fileReadCorruptFile) }
        } while true
        return output
    }
}
