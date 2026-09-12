import AppKit
import SwiftUI
import Combine
import Carbon

/// Carbon key codes and modifier masks, shared with macOS global shortcuts.
public struct StageShortcutDescriptor: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let enabled: Bool
    public let error: String?
    public let keyLabel: String
}

/// Presentation capabilities hosted by Workbench's single application shell.
/// StageKit never creates a menu-bar item or independently terminates the app.
@MainActor
public final class StageKitController: ObservableObject {
    private let coordinator: AppCoordinator
    private var observations = Set<AnyCancellable>()
    private var started = false

    public var onOpenControls: (() -> Void)? {
        didSet { coordinator.onOpenControls = onOpenControls }
    }
    public var onOpenScenes: (() -> Void)? {
        didSet { coordinator.onOpenScenes = onOpenScenes; coordinator.demoScenes.onOpen = onOpenScenes }
    }
    public var onOpenShortcuts: (() -> Void)? {
        didSet { coordinator.onOpenShortcuts = onOpenShortcuts }
    }
    public var onEditShortcuts: (() -> Void)? {
        get { onOpenShortcuts }
        set { onOpenShortcuts = newValue }
    }
    public var mayBeginInteraction: (() -> Bool)? {
        didSet { coordinator.mayBeginInteraction = mayBeginInteraction; coordinator.demoScenes.mayBeginInteraction = mayBeginInteraction }
    }
    /// Hide the shell before drawing, starting a timer or presenting a scene.
    public var onBeginActivity: (() -> Void)? {
        didSet {
            coordinator.onBeginActivity = onBeginActivity
            coordinator.demoScenes.onBeginPresentation = onBeginActivity
            coordinator.demoScenes.personas.onShow = onBeginActivity
        }
    }
    /// Supply the other modules' shortcuts so every entry point checks conflicts.
    /// Return a concise reason when the combination belongs to another module.
    public var validateExternalShortcut: ((UInt32, UInt32) -> String?)? {
        didSet {
            coordinator.validateExternalShortcut = { [weak self] code, modifiers in
                self?.validateExternalShortcut?(code, modifiers) ?? Self.reservedVoiceShortcut(code, modifiers)
            }
            if started { coordinator.setShortcutsSuspended(true); coordinator.setShortcutsSuspended(false) }
        }
    }

    public init(onOpenControls: (() -> Void)? = nil, onOpenScenes: (() -> Void)? = nil) {
        let migrationNotice = Workbench.prepareStageData()
        let settings = SettingsStore(defaults: Workbench.stageDefaults)
        let coordinator = AppCoordinator(settings: settings, embedded: true, migrationFailure: migrationNotice)
        self.coordinator = coordinator
        self.onOpenControls = onOpenControls
        self.onOpenScenes = onOpenScenes
        coordinator.onOpenControls = onOpenControls
        coordinator.onOpenScenes = onOpenScenes
        coordinator.demoScenes.onOpen = onOpenScenes
        coordinator.validateExternalShortcut = Self.reservedVoiceShortcut
        if let migrationNotice { coordinator.notice = migrationNotice }
        coordinator.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
        coordinator.demoScenes.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observations)
    }

    public var controlsView: AnyView { AnyView(ControlCenter(app: coordinator, settings: coordinator.settings)) }
    public var scenesView: AnyView { AnyView(DemoScenesView(model: coordinator.demoScenes)) }
    public var quickControlsView: AnyView { AnyView(QuickControlsView(app: coordinator, settings: coordinator.settings)) }
    public var isDrawing: Bool { coordinator.isDrawing }
    public var isPresenting: Bool { coordinator.demoScenes.isPresenting }
    public var timerText: String { coordinator.timerText }
    public var isTimerRunning: Bool { coordinator.timerRunning }
    public var notice: String? { coordinator.notice ?? coordinator.settings.notice ?? coordinator.demoScenes.notice }

    public func start() {
        guard !started else { return }
        started = true
        coordinator.start()
    }
    public func shutdown() {
        guard started else { return }
        started = false
        coordinator.shutdown()
    }
    public func draw() { coordinator.startDrawing(.pen, latched: true) }
    public func clear() { coordinator.perform(.clear) }
    public func showBoard() { coordinator.toggleBoard(.white) }
    public func showTimer() { coordinator.toggleTimer() }
    public func showScenes() { coordinator.showDemoScenes() }
    public func showPersonas() { coordinator.demoScenes.showPersonas() }
    public func endPresentation() { coordinator.demoScenes.endPresentation(); coordinator.demoScenes.personas.hideOverlay(); coordinator.hideTimer(); coordinator.escape() }
    public func escape() { coordinator.escape() }
    public func performShortcut(id: String) {
        guard let action = Action(rawValue: id) else { return }
        coordinator.perform(action)
    }
    public func setShortcutsSuspended(_ suspended: Bool) { coordinator.setShortcutsSuspended(suspended) }
    public func resetShortcuts() { coordinator.restoreShortcuts() }

    public var shortcutDescriptors: [StageShortcutDescriptor] {
        Action.allCases.map { action in
            let shortcut = coordinator.settings.value.shortcut(for: action)
            return StageShortcutDescriptor(id: action.rawValue, label: action.title,
                keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, enabled: shortcut.enabled,
                error: coordinator.shortcutFailures[action], keyLabel: shortcut.label)
        }
    }

    /// Returns a validation failure without changing the saved shortcut.
    @discardableResult
    public func updateShortcut(id: String, keyCode: UInt32, modifiers: UInt32, enabled: Bool) -> String? {
        guard let action = Action(rawValue: id) else { return "That action is no longer available." }
        let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers, enabled: enabled)
        if enabled {
            guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return "Include Control, Option or Command." }
            if let message = coordinator.validateExternalShortcut?(keyCode, modifiers) { return message }
            if let conflict = Action.allCases.first(where: { $0 != action && coordinator.settings.value.shortcut(for: $0) == shortcut }) {
                return "That shortcut belongs to \(conflict.title). Choose another combination."
            }
        }
        coordinator.settings.value.shortcuts[action.rawValue] = shortcut
        return nil
    }

    private static func reservedVoiceShortcut(_ code: UInt32, _ modifiers: UInt32) -> String? {
        guard modifiers == UInt32(controlKey | optionKey), [UInt32(kVK_Space), UInt32(kVK_ANSI_V), UInt32(kVK_ANSI_J)].contains(code) else { return nil }
        return "This combination is reserved for Voice. Choose another combination."
    }
}
