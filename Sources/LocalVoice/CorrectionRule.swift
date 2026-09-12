import Foundation

struct RememberedCorrection {
    let written: String
    let beforeRules: [Replacement]
    let afterRules: [Replacement]
    let beforeDraft: String
    let afterDraft: String
    let appliedRevision: UInt64
}

/// A value proposal only: the caller decides whether to save the rule and whether
/// to apply previewText. Recreate it from current draft/rules before committing.
struct CorrectionRuleProposal {
    let rule: Replacement
    let previousRule: Replacement?
    let updatedRules: [Replacement]
    let sourceDraft: String
    let previewText: String
    /// Whole phrase occurrences, including occurrences already using the desired casing.
    let matchCount: Int
    var replacesExisting: Bool { previousRule != nil && previousRule != rule }
    var isAlreadyRemembered: Bool { previousRule == rule }
    var changesDraft: Bool { sourceDraft != previewText }
}

enum CorrectionRuleError: LocalizedError, Equatable {
    case emptyField(String)
    case tooLong(String)
    case unsupportedCharacters(String)
    case noChange
    case duplicateRules(heard: String, count: Int)

    var errorDescription: String? {
        switch self {
        case .emptyField(let field): return "Add some text to \(field)."
        case .tooLong(let field): return "Keep \(field) to \(CorrectionRule.maximumCharacters) characters or fewer."
        case .unsupportedCharacters(let field): return "Use one line of text in \(field), without tabs or control characters."
        case .noChange: return "These already match. There is no correction to remember."
        case .duplicateRules(let heard, let count):
            return "There are \(count) dictionary rules for “\(heard)”. Remove the duplicates in Dictionary before remembering this correction."
        }
    }
}

enum CorrectionRule {
    static let maximumCharacters = 120

    /// Matches TextRules' case-insensitive literal phrase and Unicode word boundaries.
    /// The current draft preview applies this rule alone, without trimming the draft
    /// or replaying unrelated dictionary rules. No matches still permits future use.
    static func propose(heard: String, written: String, draft: String, replacements: [Replacement]) throws -> CorrectionRuleProposal {
        let heard = try validated(heard, field: "Heard")
        let written = try validated(written, field: "Write instead")
        guard heard != written else { throw CorrectionRuleError.noChange }

        let literal = NSRegularExpression.escapedPattern(for: heard)
        let identity = try NSRegularExpression(pattern: "\\A(?:" + literal + ")\\z", options: [.caseInsensitive])
        let matches = replacements.indices.filter { index in
            let existing = replacements[index].heard.trimmingCharacters(in: .whitespacesAndNewlines)
            return identity.firstMatch(in: existing, range: NSRange(existing.startIndex..., in: existing)) != nil
        }
        guard matches.count <= 1 else { throw CorrectionRuleError.duplicateRules(heard: heard, count: matches.count) }

        let previous = matches.first.map { replacements[$0] }
        var rule = Replacement(heard: heard, written: written)
        if let previous { rule.id = previous.id }
        var updated = replacements
        if let index = matches.first { updated[index] = rule }
        else { updated.append(rule) }

        let pattern = "(?<![\\p{L}\\p{N}_])" + literal + "(?![\\p{L}\\p{N}_])"
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(draft.startIndex..., in: draft)
        let count = regex.numberOfMatches(in: draft, range: range)
        let preview = regex.stringByReplacingMatches(in: draft, range: range,
                                                     withTemplate: NSRegularExpression.escapedTemplate(for: written))
        return CorrectionRuleProposal(rule: rule, previousRule: previous, updatedRules: updated,
                                      sourceDraft: draft, previewText: preview, matchCount: count)
    }

    private static func validated(_ source: String, field: String) throws -> String {
        // Inspect before trimming so pasted line breaks or invisible controls cannot
        // silently turn into a different rule from the one the user entered.
        guard !source.unicodeScalars.contains(where: {
            CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }) else { throw CorrectionRuleError.unsupportedCharacters(field) }
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CorrectionRuleError.emptyField(field) }
        guard value.count <= maximumCharacters else { throw CorrectionRuleError.tooLong(field) }
        return value
    }
}
