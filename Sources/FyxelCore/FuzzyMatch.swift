import Foundation

/// Sublime Text / VS Code-style fuzzy matching. Every query character has to appear in the
/// text in order; matches at word starts and runs of consecutive characters score higher,
/// gaps between matched characters cost a little. Case- and diacritic-insensitive.
public enum FuzzyMatch {
    public struct Result: Sendable, Equatable {
        public var score: Int
        /// Offsets (in `Character`s of the text) of the matched characters, ascending.
        public var positions: [Int]
    }

    static let startBonus = 10, wordBonus = 8, camelBonus = 6, digitBonus = 4
    static let consecutiveBonus = 5, gapPenalty = 1, maxLeadingPenalty = 3

    /// The best-scoring alignment of `query` in `text`, or nil if it doesn't match at all.
    /// Scattered matches can score below zero; callers usually want `score > 0`.
    public static func match(_ query: String, _ text: String) -> Result? {
        let q = query.map(fold), orig = Array(text), t = orig.map(fold)
        let n = q.count, m = t.count
        guard n > 0 else { return Result(score: 0, positions: []) }
        guard n <= m else { return nil }

        let none = Int.min / 4
        let bonus = (0..<m).map { boundaryBonus(orig, $0) }
        // score[i][j]: best score with q[i] matched at t[j]; from[i][j]: where q[i-1] matched.
        var score = [[Int]](repeating: [Int](repeating: none, count: m), count: n)
        var from = [[Int]](repeating: [Int](repeating: -1, count: m), count: n)

        for i in 0..<n {
            // Best score[i-1][k] - gap penalty, over k <= j-2 (i.e. with at least one char skipped).
            var gapBest = none, gapAt = -1
            for j in i..<m {
                if i > 0, j >= 2 {
                    if gapBest != none { gapBest -= gapPenalty }
                    let c = score[i - 1][j - 2]
                    if c != none, c - gapPenalty > gapBest { gapBest = c - gapPenalty; gapAt = j - 2 }
                }
                guard q[i] == t[j] else { continue }
                if i == 0 {
                    score[i][j] = 1 + bonus[j] - min(j, maxLeadingPenalty)
                    continue
                }
                var best = gapBest, at = gapAt
                if j >= 1, score[i - 1][j - 1] != none, score[i - 1][j - 1] + consecutiveBonus >= best {
                    best = score[i - 1][j - 1] + consecutiveBonus; at = j - 1
                }
                guard best != none else { continue }
                score[i][j] = best + 1 + bonus[j]
                from[i][j] = at
            }
        }

        var end = -1, top = none
        for j in 0..<m where score[n - 1][j] > top { top = score[n - 1][j]; end = j }
        guard end >= 0 else { return nil }
        var positions = [Int](repeating: 0, count: n)
        var j = end
        for i in stride(from: n - 1, through: 0, by: -1) {
            positions[i] = j
            j = from[i][j]
        }
        // Prefer shorter texts when the match itself is equally good ("LAN" over "LAN & DHCP Server").
        return Result(score: top - (m - n) / 12, positions: positions)
    }

    static func fold(_ c: Character) -> Character {
        String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).first ?? c
    }

    static func boundaryBonus(_ s: [Character], _ j: Int) -> Int {
        guard j > 0 else { return startBonus }
        let prev = s[j - 1], cur = s[j]
        if !prev.isLetter && !prev.isNumber { return cur.isLetter || cur.isNumber ? wordBonus : 0 }
        if prev.isLowercase && cur.isUppercase { return camelBonus }
        if !prev.isNumber && cur.isNumber { return digitBonus }
        return 0
    }
}
