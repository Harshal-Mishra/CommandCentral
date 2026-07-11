import Foundation

enum Fuzzy {
    /// Subsequence fuzzy match. Returns nil when `query` is not a
    /// subsequence of `target`; higher scores are better matches.
    static func score(query: String, target: String) -> Int? {
        let q = Array(query.lowercased())
        let t = Array(target.lowercased())
        guard !q.isEmpty else { return 0 }
        guard q.count <= t.count else { return nil }

        var score = 0
        var qi = 0
        var previousMatched = false
        for (ti, ch) in t.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                var bonus = 1
                if ti == 0 {
                    bonus += 15 // match at very start
                } else if !t[ti - 1].isLetter && !t[ti - 1].isNumber {
                    bonus += 10 // match at word boundary
                }
                if previousMatched { bonus += 5 } // consecutive run
                score += bonus
                qi += 1
                previousMatched = true
            } else {
                previousMatched = false
            }
        }
        guard qi == q.count else { return nil }
        // Slightly prefer shorter targets when scores tie.
        return score * 100 - t.count
    }
}
