import Foundation

/// Session-only visibility policy. Pointer movement over the demo is not a
/// reveal request; only entering the top edge or using a control is deliberate.
struct PresentationControlsPolicy: Equatable {
    enum Hold: Hashable { case topEdge, toolbarHover, keyboardFocus, sheet, pinned, voiceOver }
    static let hideDelay: TimeInterval = 4
    static let topEdgeHeight: Double = 24
    private(set) var isVisible = true
    private(set) var holds = Set<Hold>()
    private(set) var hideDeadline: TimeInterval?

    mutating func reveal(at now: TimeInterval) {
        isVisible = true
        hideDeadline = holds.isEmpty ? now + Self.hideDelay : nil
    }

    mutating func setHold(_ hold: Hold, active: Bool, at now: TimeInterval) {
        guard holds.contains(hold) != active else { return }
        if active { holds.insert(hold) } else { holds.remove(hold) }
        reveal(at: now)
    }

    mutating func pointerMoved(y: Double?, at now: TimeInterval) {
        let atTopEdge = y.map { $0 >= 0 && $0 <= Self.topEdgeHeight } ?? false
        setHold(.topEdge, active: atTopEdge, at: now)
    }

    mutating func hideIfDue(at now: TimeInterval) {
        guard holds.isEmpty, let hideDeadline, now >= hideDeadline else { return }
        isVisible = false
        self.hideDeadline = nil
    }

    static func isRevealCommand(characters: String?, command: Bool, option: Bool, control: Bool) -> Bool {
        // charactersIgnoringModifiers still respects Shift, so layouts where
        // slash requires Shift work without claiming a particular physical key.
        characters == "/" && command && !option && !control
    }
}
