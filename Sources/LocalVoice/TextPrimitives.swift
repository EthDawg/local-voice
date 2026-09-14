import Foundation

struct Replacement: Codable, Identifiable, Equatable {
    var id = UUID()
    var heard: String
    var written: String
}

enum TextRules {
    static func apply(_ text: String, replacements: [Replacement]) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in replacements where !item.heard.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: item.heard) + "(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: NSRegularExpression.escapedTemplate(for: item.written))
        }
        return result
    }
    static func wordCount(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

struct Transcript: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
    var seconds: Double
    var rawText: String? = nil
    var cleanupMethod: String? = nil
}

enum TranscriptHistory {
    static let limit = 100
    static func adding(_ capture: Transcript, to history: [Transcript]) -> [Transcript] {
        // Separate recordings remain separate even when their words are identical.
        Array(([capture] + history.filter { $0.id != capture.id }).prefix(limit))
    }
    static func matching(_ history: [Transcript], query: String) -> [Transcript] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? history : history.filter {
            $0.text.localizedCaseInsensitiveContains(query) || ($0.rawText?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
