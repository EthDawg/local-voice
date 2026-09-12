import AppKit

/// No hover, timer or capture-status transition can open or dismiss controls.
/// The collapsed tile remains an ordinary accessible button throughout a demo.
struct PresentationControlsPolicy: Equatable {
    private(set) var isExpanded = false
    mutating func open() { isExpanded = true }
    mutating func close() { isExpanded = false }
    mutating func toggle() { isExpanded.toggle() }
    /// True consumes Escape; false lets the presentation end.
    mutating func handleEscape() -> Bool {
        guard isExpanded else { return false }
        close(); return true
    }
    static func isRevealCommand(characters: String?, command: Bool, option: Bool, control: Bool) -> Bool {
        characters == "/" && command && !option && !control
    }
}

/// Job-specific placement only. Expanded state is never restored at launch.
struct PresentationControlPlacement: Codable, Equatable {
    var version = 1
    var anchor: FloatingControlAnchor? = .right
    var x = 1.0
    var y = 0.5

    func validated() throws -> PresentationControlPlacement {
        guard version == 1, x.isFinite, y.isFinite else { throw CocoaError(.coderReadCorrupt) }
        var value = self; value.x = min(1, max(0, x)); value.y = min(1, max(0, y))
        return value
    }
    func frame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        if let anchor { return FloatingControlGeometry.frame(anchor: anchor, size: size, visibleFrame: visibleFrame) }
        let lower = FloatingControlGeometry.frame(anchor: .bottomLeft, size: size, visibleFrame: visibleFrame)
        let upper = FloatingControlGeometry.frame(anchor: .topRight, size: size, visibleFrame: visibleFrame)
        let frame = NSRect(x: lower.minX + (upper.minX - lower.minX) * x,
                           y: lower.minY + (upper.minY - lower.minY) * y, width: lower.width, height: lower.height)
        return FloatingControlGeometry.clamp(frame, to: visibleFrame)
    }
    mutating func move(to frame: NSRect, in visibleFrame: NSRect, anchor: FloatingControlAnchor?) {
        self.anchor = anchor
        let lower = FloatingControlGeometry.frame(anchor: .bottomLeft, size: frame.size, visibleFrame: visibleFrame)
        let upper = FloatingControlGeometry.frame(anchor: .topRight, size: frame.size, visibleFrame: visibleFrame)
        x = upper.minX > lower.minX ? min(1, max(0, (frame.minX - lower.minX) / (upper.minX - lower.minX))) : 0.5
        y = upper.minY > lower.minY ? min(1, max(0, (frame.minY - lower.minY) / (upper.minY - lower.minY))) : 0.5
    }
}
