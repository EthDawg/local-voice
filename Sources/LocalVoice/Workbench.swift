// Workbench shell contract v2. Keep this file identical in the suite apps.
import AppKit
import SwiftUI

enum Workbench {
    static let name = "Workbench"
    static var isPreview: Bool { Bundle.main.object(forInfoDictionaryKey: "WorkbenchChannel") as? String == "preview" }
    static var productionIsRunning: Bool {
        guard isPreview, let identifier = Bundle.main.bundleIdentifier, identifier.hasSuffix(".preview") else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: String(identifier.dropLast(".preview".count))).isEmpty
    }
    static var displayName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? name }
    static var suiteDomain: String { "com.ethdawg.workbench" + (isPreview ? ".preview" : "") }
    static func supportDirectory(component: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(component + (isPreview ? " Preview" : ""), isDirectory: true)
    }
    // Seed once from a read-only snapshot. Subsequent updates never overwrite Preview data.
    // Explicit file allowlist avoids copying model caches, credentials or unrelated state.
    static func preparePreviewData(component: String, files: [String]) {
        guard isPreview, let identifier = Bundle.main.bundleIdentifier, identifier.hasSuffix(".preview") else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "workbench.previewSeeded.v1") else { return }
        let originalID = String(identifier.dropLast(".preview".count))
        let current = defaults.persistentDomain(forName: identifier) ?? [:]
        for (key, value) in defaults.persistentDomain(forName: originalID) ?? [:] where current[key] == nil {
            defaults.set(value, forKey: key)
        }
        let suite = UserDefaults(suiteName: suiteDomain)!
        if suite.object(forKey: "appearance") == nil,
           let appearance = defaults.persistentDomain(forName: "com.ethdawg.workbench")?["appearance"] {
            suite.set(appearance, forKey: "appearance")
        }
        let destination = supportDirectory(component: component)
        let source = destination.deletingLastPathComponent().appendingPathComponent(component, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for file in files where !file.contains("/") && file != ".." {
                let from = source.appendingPathComponent(file), to = destination.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) {
                    try FileManager.default.copyItem(at: from, to: to)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: to.path)
                }
            }
            defaults.set(true, forKey: "workbench.previewSeeded.v1")
        } catch {
            // Preserve the original and retry any missing snapshot files next launch.
            NSLog("Workbench Preview could not finish its initial snapshot: %@", error.localizedDescription)
        }
    }
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
        let suffix = isPreview ? " Preview" : ""
        let bundleName = "Workbench \(app)\(suffix).app"
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/" + bundleName)
        let global = URL(fileURLWithPath: "/Applications/" + bundleName)
        let id = (app == "Voice" ? "com.ethdawg.localvoice" : "local.ethan.StageMark") + (isPreview ? ".preview" : "")
        let location = [home, global].first { FileManager.default.fileExists(atPath: $0.path) }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        if let location {
            NSWorkspace.shared.openApplication(at: location, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

final class WorkbenchSettings: ObservableObject {
    enum Appearance: String, CaseIterable { case system = "System", light = "Light", dark = "Dark" }
    static let shared = WorkbenchSettings()
    #if APP_STORE
    // Store editions keep preferences within their own sandbox container.
    private let defaults = UserDefaults.standard
    #else
    private let defaults = UserDefaults(suiteName: Workbench.suiteDomain)!
    #endif
    private let notification = Notification.Name(Workbench.suiteDomain + ".appearance")
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
        #if APP_STORE
        // Use AppKit appearance rather than reading a system-owned defaults key.
        NSApp?.appearance = nil
        systemIsDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #else
        systemIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        #endif
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
                Text(Workbench.isPreview ? "WORKBENCH · PREVIEW" : "WORKBENCH").font(.system(size: 8, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                Text(title).font(.system(size: 14, weight: .semibold))
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                if Workbench.productionIsRunning {
                    Text("Quit production to use the same shortcuts here.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
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
        } label: { Label(Workbench.isPreview ? "Workbench Preview" : "Workbench", systemImage: "square.grid.2x2") }
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
