import Foundation

public enum EditDistance: Sendable {
    /// Levenshtein distance; early-exits above `limit`.
    public static func between(_ a: String, _ b: String, limit: Int = 2) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if abs(aChars.count - bChars.count) > limit { return limit + 1 }
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        var prev = Array(0...bChars.count)
        var cur = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                cur[j] = min(
                    prev[j] + 1,
                    cur[j - 1] + 1,
                    prev[j - 1] + cost
                )
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&prev, &cur)
        }
        return prev[bChars.count]
    }
}
