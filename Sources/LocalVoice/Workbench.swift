// Workbench shell contract v1. Keep this file identical in the suite apps.
import AppKit
import SwiftUI

enum Workbench {
    static let name = "Workbench"
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.43, green: 0.89, blue: 0.73, alpha: 1)
            : NSColor(srgbRed: 0.04, green: 0.43, blue: 0.32, alpha: 1)
    })
    static let border = Color.primary.opacity(0.08)
    static let controlWidth: CGFloat = 370
    static func open(_ app: String) {
        let location = app == "Voice"
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Workbench Voice.app")
            : URL(fileURLWithPath: "/Applications/Workbench StageMark.app")
        if FileManager.default.fileExists(atPath: location.path) {
            NSWorkspace.shared.openApplication(at: location, configuration: NSWorkspace.OpenConfiguration())
        } else {
            let id = app == "Voice" ? "com.ethdawg.localvoice" : "local.ethan.StageMark"
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}

final class WorkbenchSettings: ObservableObject {
    enum Appearance: String, CaseIterable { case system = "System", light = "Light", dark = "Dark" }
    static let shared = WorkbenchSettings()
    private let defaults = UserDefaults(suiteName: "com.ethdawg.workbench")!
    private let notification = Notification.Name("com.ethdawg.workbench.appearance")
    private var observer: NSObjectProtocol?
    private var systemObserver: NSObjectProtocol?
    @Published private(set) var systemIsDark = false
    var colorScheme: ColorScheme { appearance == .dark || (appearance == .system && systemIsDark) ? .dark : .light }
    @Published private(set) var appearance: Appearance = .system
    init() {
        refresh()
        systemObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        observer = DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }
    func setAppearance(_ value: Appearance) {
        defaults.set(value.rawValue, forKey: "appearance"); defaults.synchronize()
        refresh(); DistributedNotificationCenter.default().postNotificationName(notification, object: nil, userInfo: nil, deliverImmediately: true)
    }
    private func refresh() {
        defaults.synchronize(); UserDefaults.standard.synchronize()
        systemIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        NSApp?.appearance = appearance == .system ? nil : NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }
    deinit { if let observer { DistributedNotificationCenter.default().removeObserver(observer) }; if let systemObserver { DistributedNotificationCenter.default().removeObserver(systemObserver) } }
}

struct WorkbenchHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(Workbench.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("WORKBENCH").font(.system(size: 8, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                Text(title).font(.system(size: 14, weight: .semibold))
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
    }
}
struct WorkbenchSwitcher: View {
    var beforeOpen: () -> Void = {}
    var body: some View {
        Menu {
            Button("Voice · dictate and read") { beforeOpen(); Workbench.open("Voice") }
            Button("StageMark · draw and present") { beforeOpen(); Workbench.open("StageMark") }
        } label: { Label("Workbench", systemImage: "square.grid.2x2") }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).accessibilityLabel("Workbench apps")
    }
}
struct WorkbenchAppearancePicker: View {
    @ObservedObject private var suite = WorkbenchSettings.shared
    var body: some View {
        Picker("Suite appearance", selection: Binding(get: { suite.appearance }, set: { suite.setAppearance($0) })) {
            ForEach(WorkbenchSettings.Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }
}

struct WorkbenchTheme: ViewModifier {
    @ObservedObject private var suite = WorkbenchSettings.shared
    func body(content: Content) -> some View {
        content.preferredColorScheme(suite.colorScheme)
    }
}
extension View {
    func workbenchTheme() -> some View { modifier(WorkbenchTheme()) }
}
