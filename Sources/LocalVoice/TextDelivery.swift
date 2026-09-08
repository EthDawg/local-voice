import AppKit

@MainActor
final class TextDelivery {
    struct Target {
        var app: NSRunningApplication
        var element: AXUIElement?
        var value: String?
    }
    static func capture(app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) -> Target? {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = focusedElement(app.processIdentifier)
        return Target(app: app, element: element, value: element.flatMap { string($0, kAXValueAttribute) })
    }
    static func focusedElement(_ pid: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func string(_ element: AXUIElement, _ key: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value as? String
    }
    static func eligible(_ target: Target) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier,
              let captured = target.element, let current = focusedElement(target.app.processIdentifier), CFEqual(captured, current),
              string(current, kAXSubroleAttribute) != kAXSecureTextFieldSubrole else { return false }
        return true
    }
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    static func deliver(_ text: String, target: Target?, mode: DeliveryMode, restoreClipboard: Bool) async -> String {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        copy(text)
        let ownedChange = pasteboard.changeCount
        guard mode == .paste, let target else { return "Transcript ready and copied." }
        guard AXIsProcessTrusted() else { return "Copied · enable Accessibility in quick controls for automatic paste." }
        guard eligible(target) else { return "Copied · focus changed, so nothing was pasted. Press ⌘V when ready." }
        // Snapshot immediately before insertion so an unrelated user edit is not mistaken for our paste.
        let before = target.element.flatMap { string($0, kAXValueAttribute) }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return "Copied · paste could not start. Press ⌘V." }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 450_000_000)
        let after = target.element.flatMap { string($0, kAXValueAttribute) }
        let confirmed = after != before && after?.contains(text) == true
        if confirmed, restoreClipboard, pasteboard.changeCount == ownedChange {
            pasteboard.clearContents(); if !previous.isEmpty { pasteboard.writeObjects(previous) }
        }
        return confirmed ? "Pasted into \(target.app.localizedName ?? "your app")." : "Paste sent · transcript stays copied because insertion could not be confirmed."
    }
}
