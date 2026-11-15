import Foundation

public enum StringSimilarity {
    /// Jaro–Winkler similarity in 0...1. Robust to typos and transpositions in short strings like names.
    public static func jaroWinkler(_ a: String, _ b: String) -> Double {
        let s1 = Array(a), s2 = Array(b)
        if s1.isEmpty && s2.isEmpty { return 1 }
        if s1.isEmpty || s2.isEmpty { return 0 }
        if s1 == s2 { return 1 }

        let window = max(0, max(s1.count, s2.count) / 2 - 1)
        var matched1 = [Bool](repeating: false, count: s1.count)
        var matched2 = [Bool](repeating: false, count: s2.count)
        var matches = 0
        for i in s1.indices {
            let lo = max(0, i - window), hi = min(s2.count - 1, i + window)
            guard lo <= hi else { continue }
            for j in lo...hi where !matched2[j] && s1[i] == s2[j] {
                matched1[i] = true
                matched2[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }

        var transpositions = 0
        var k = 0
        for i in s1.indices where matched1[i] {
            while !matched2[k] { k += 1 }
            if s1[i] != s2[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(s1.count) + m / Double(s2.count) + (m - Double(transpositions) / 2) / m) / 3

        var prefix = 0
        while prefix < min(4, s1.count, s2.count) && s1[prefix] == s2[prefix] { prefix += 1 }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }
}
