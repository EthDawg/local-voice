import Foundation

enum CorrectionRuleChecks {
    static func run() throws {
        var passed = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw VoiceError.message("CORRECTION_RULE_CHECK_FAILED: \(name)") }
            passed += 1
        }
        func rejects(_ expected: CorrectionRuleError, heard: String, written: String, rules: [Replacement] = []) throws {
            do {
                _ = try CorrectionRule.propose(heard: heard, written: written, draft: "Untouched draft", replacements: rules)
                throw VoiceError.message("CORRECTION_RULE_CHECK_FAILED: accepted invalid correction")
            } catch let error as CorrectionRuleError {
                try check(error == expected, "validation must explain the actual problem")
            }
        }
        try rejects(.emptyField("Heard"), heard: "   ", written: "GitHub")
        try rejects(.emptyField("Write instead"), heard: "git hub", written: "   ")
        try rejects(.tooLong("Heard"), heard: String(repeating: "a", count: 121), written: "b")
        try rejects(.tooLong("Write instead"), heard: "a", written: String(repeating: "b", count: 121))
        for invalid in ["git\nhub", "git\rhub", "git\thub", "git\u{0}hub", "git\u{2028}hub", "git\u{200B}hub", "\ngit hub"] {
            try rejects(.unsupportedCharacters("Heard"), heard: invalid, written: "GitHub")
            try rejects(.unsupportedCharacters("Write instead"), heard: "git hub", written: invalid)
        }
        try rejects(.noChange, heard: " GitHub ", written: "GitHub")
        let boundary = try CorrectionRule.propose(heard: String(repeating: "a", count: 120), written: String(repeating: "b", count: 120), draft: "", replacements: [])
        try check(boundary.rule.heard.count == 120 && boundary.rule.written.count == 120, "120 character phrases remain valid")

        let spaced = try CorrectionRule.propose(heard: " git hub ", written: " GitHub ", draft: " \nGit hub, GIT HUB!\t ", replacements: [])
        try check(spaced.rule.heard == "git hub" && spaced.rule.written == "GitHub", "trim the rule fields")
        try check(spaced.previewText == " \nGitHub, GitHub!\t " && spaced.matchCount == 2, "preserve draft whitespace and preview every phrase occurrence")
        try check(spaced.sourceDraft == " \nGit hub, GIT HUB!\t " && spaced.changesDraft, "retain the preview's source for stale-draft checks")
        try check(spaced.updatedRules == [spaced.rule] && !spaced.replacesExisting && !spaced.isAlreadyRemembered, "new correction adds exactly one rule")

        let whole = try CorrectionRule.propose(heard: "cat", written: "kitten", draft: "cat Cat concatenate catfish bobcat cat_1 cat2 2cat cat.", replacements: [])
        try check(whole.previewText == "kitten kitten concatenate catfish bobcat cat_1 cat2 2cat kitten." && whole.matchCount == 3,
                  "whole-word boundaries reject substring, number and underscore matches")
        let casing = try CorrectionRule.propose(heard: "github", written: "GitHub", draft: "github GITHUB GitHub", replacements: [])
        try check(casing.previewText == "GitHub GitHub GitHub" && casing.matchCount == 3, "case-only correction remains valid")
        let alreadyCased = try CorrectionRule.propose(heard: "github", written: "GitHub", draft: "GitHub", replacements: [])
        try check(alreadyCased.matchCount == 1 && !alreadyCased.changesDraft, "count matching occurrences without claiming a change to already-correct text")

        let literal = try CorrectionRule.propose(heard: "a.b", written: "$1\\files", draft: "a.b axb A.B", replacements: [])
        try check(literal.previewText == "$1\\files axb $1\\files" && literal.matchCount == 2, "escape both regex metacharacters and replacement templates")
        let punctuation = try CorrectionRule.propose(heard: "c++", written: "C++", draft: "c++ (c++) c+++ abc++", replacements: [])
        try check(punctuation.previewText == TextRules.apply("c++ (c++) c+++ abc++", replacements: [punctuation.rule]),
                  "punctuation phrases match the production transcription rule semantics")
        let unicode = try CorrectionRule.propose(heard: "café", written: "Coffee", draft: "café, CAFÉ, cafés, décafé", replacements: [])
        try check(unicode.previewText == "Coffee, Coffee, cafés, décafé" && unicode.matchCount == 2, "Unicode casing and whole-word boundaries")
        let absent = try CorrectionRule.propose(heard: "git hub", written: "GitHub", draft: " \nNo match here.\n ", replacements: [])
        try check(absent.matchCount == 0 && !absent.changesDraft && absent.previewText == absent.sourceDraft,
                  "future-only correction does not alter a draft with no matches")

        let before = Replacement(heard: "alpha", written: "A")
        let old = Replacement(heard: "GIT HUB", written: "Github")
        let after = Replacement(heard: "omega", written: "Z")
        let rules = [before, old, after]
        let updated = try CorrectionRule.propose(heard: "git hub", written: "GitHub", draft: "alpha git hub omega", replacements: rules)
        try check(updated.rule.id == old.id && updated.previousRule == old && updated.replacesExisting,
                  "case-insensitive existing rule update preserves its ID and reports replacement")
        try check(updated.updatedRules.count == 3 && updated.updatedRules[0] == before && updated.updatedRules[1] == updated.rule && updated.updatedRules[2] == after,
                  "update preserves unrelated rules and their order")
        try check(updated.previewText == "alpha GitHub omega", "review preview applies only the chosen correction")
        try check(rules == [before, old, after], "proposal creation never mutates input rules")
        let remembered = try CorrectionRule.propose(heard: "git hub", written: "GitHub", draft: "git hub", replacements: updated.updatedRules)
        try check(remembered.isAlreadyRemembered && !remembered.replacesExisting && remembered.updatedRules == updated.updatedRules,
                  "remembering the same rule does not add a duplicate")
        try rejects(.duplicateRules(heard: "git hub", count: 2), heard: "git hub", written: "GitHub",
                    rules: [old, Replacement(heard: "Git Hub", written: "GitLab")])
        try rejects(.duplicateRules(heard: "git hub", count: 2), heard: "git hub", written: "GitHub",
                    rules: [old, Replacement(heard: "git hub", written: old.written)])
        let unrelatedDuplicates = [Replacement(heard: "other", written: "one"), Replacement(heard: "OTHER", written: "two")]
        let independent = try CorrectionRule.propose(heard: "git hub", written: "GitHub", draft: "", replacements: unrelatedDuplicates)
        try check(Array(independent.updatedRules.prefix(2)) == unrelatedDuplicates && independent.updatedRules.count == 3,
                  "unrelated duplicate state is preserved rather than silently repaired")
        try check(TextRules.apply("  ALPHA git hub omega  ", replacements: updated.updatedRules) == "A GitHub Z",
                  "a subsequent transcription observes the saved correction through production TextRules")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CorrectionRuleChecks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        let session = SavedState(draft: updated.previewText, history: [Transcript(text: "Earlier capture", seconds: 2)], replacements: updated.updatedRules, rawDraft: "Original unchanged")
        try store.save(session)
        let restored = try store.load()
        try check(restored.replacements == updated.updatedRules && restored.replacements[1].id == old.id,
                  "dictionary upsert and identity survive the real StateStore round trip")
        try check(restored.draft == updated.previewText && restored.rawDraft == session.rawDraft && restored.history.first?.text == "Earlier capture",
                  "saving the corrected draft preserves its original and earlier capture")
        try check(TextRules.apply("Next GIT HUB capture", replacements: restored.replacements) == "Next GitHub capture",
                  "a later transcription uses the persisted correction")
        print("CORRECTION_RULE_CHECKS_OK: \(passed) checks passed")
    }
}
