import AppKit
import SwiftUI

enum NativePresentationApp: String, CaseIterable {
    case quickTime, iPhoneMirroring
    var title: String { self == .quickTime ? "QuickTime Player" : "iPhone Mirroring" }
    var bundleIdentifier: String { self == .quickTime ? "com.apple.QuickTimePlayerX" : "com.apple.ScreenContinuity" }
    var applicationURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }
    var isAvailable: Bool { applicationURL != nil }

    func open(onError: @escaping (String) -> Void) {
        guard let url = applicationURL else { onError("\(title) is not installed on this Mac."); return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error { DispatchQueue.main.async { onError("\(title) could not open: \(error.localizedDescription)") } }
        }
    }
}

/// Apple's apps are useful alternatives. iPhone Mirroring remains a separate
/// Apple-controlled window; Workbench does not claim to embed or automate it.
struct NativePresentationApps: View {
    var onError: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple alternatives").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(NativePresentationApp.allCases, id: \.self) { app in
                    Button(app.title) { app.open(onError: onError) }
                        .disabled(!app.isAvailable)
                        .help(app.isAvailable ? "Open \(app.title) in its own window" : "Not installed on this Mac")
                }
            }
            Text("QuickTime shows a device over USB. iPhone Mirroring works in its own window on supported Macs; share that window directly in your meeting.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
