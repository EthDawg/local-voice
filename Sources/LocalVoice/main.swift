import AppKit
import SwiftUI
import Carbon
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var window: NSWindow!
    var overlay: NSPanel!
    var model: AppModel!
    var statusItem: NSStatusItem!
    let hotkeys = VoiceHotkeys()
    var popover: NSPopover!
    var recorderMonitor: Any?
    var menuTarget: TextDelivery.Target?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = WorkbenchSettings.shared
        model = AppModel()
        window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(model: model)))
        window.title = "Workbench Voice"
        window.setContentSize(NSSize(width: 1060, height: 760))
        window.minSize = NSSize(width: 900, height: 700)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false; window.center()
        overlay = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 70), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isFloatingPanel = true; overlay.level = .floating; overlay.isOpaque = false; overlay.backgroundColor = .clear
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.contentView = NSHostingView(rootView: RecordingOverlay(model: model))
        popover = NSPopover(); popover.behavior = .transient; popover.animates = false; popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: VoiceQuickControls(model: model)); popover.contentSize = VoiceQuickControls.size
        model.onPhaseChange = { [weak self] in self?.updateRecordingUI() }
        model.onShortcutsChanged = { [weak self] in self?.registerShortcuts() }
        model.onEditShortcut = { [weak self] id in self?.editShortcut(id) }
        model.onShowEditor = { [weak self] page in self?.model.page = page; self?.showWindow() }
        model.onMenuRecording = { [weak self] in self?.menuRecording() }
        model.onCloseMenu = { [weak self] in self?.closeControls() }
        model.onPasteLast = { [weak self] in self?.pasteLast() }
        hotkeys.onKey = { [weak self] id, down in
            guard let self else { return }
            if id == 1 { self.model.shortcutChanged(down: down) }
            else if down { self.toggleControls() }
        }
        setupMenus(); registerShortcuts(); showControls()
    }
    func registerShortcuts() {
        guard model.editingShortcut == nil else { return }
        hotkeys.register(model.preferences); model.shortcutFailures = hotkeys.failures
    }
    func editShortcut(_ id: UInt32) {
        finishEditing(); hotkeys.unregister(); model.editingShortcut = id
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.finishEditing(); return nil }
            var shortcut = VoiceShortcut(event: event)
            if event.keyCode == 51 && shortcut.modifiers == 0 { shortcut.enabled = false }
            else if shortcut.modifiers & UInt32(controlKey | optionKey | cmdKey) == 0 {
                self.model.shortcutFailures[id] = "Include Control, Option, or Command."; return nil
            }
            let other = id == 1 ? self.model.preferences.controlsShortcut : self.model.preferences.dictationShortcut
            if shortcut.enabled && shortcut == other { self.model.shortcutFailures[id] = "That shortcut is already assigned in Voice."; return nil }
            if id == 1 { self.model.preferences.dictationShortcut = shortcut }
            else { self.model.preferences.controlsShortcut = shortcut }
            self.finishEditing(); return nil
        }
    }
    func finishEditing() {
        if let recorderMonitor { NSEvent.removeMonitor(recorderMonitor); self.recorderMonitor = nil }
        guard model != nil else { return }
        model.editingShortcut = nil; registerShortcuts()
    }
    private func setupMenus() {
        let main = NSMenu(); let application = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Workbench Voice", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Workbench Voice", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Workbench Voice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = appMenu; main.addItem(application)
        let edit = NSMenuItem(); edit.title = "Edit"; let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        edit.submenu = editMenu; main.addItem(edit)
        let windows = NSMenuItem(); windows.title = "Window"; let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Open editor", action: #selector(showWindow), keyEquivalent: "0")
        windows.submenu = menu; main.addItem(windows); NSApp.mainMenu = main; NSApp.windowsMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = NSStatusItem.AutosaveName("LocalVoice.MenuBar")
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp]); updateRecordingUI()
    }
    @objc func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Quick controls", action: #selector(toggleControls), keyEquivalent: "")
            menu.addItem(withTitle: "Open editor", action: #selector(showWindow), keyEquivalent: "")
            menu.addItem(.separator()); menu.addItem(withTitle: "Quit Workbench Voice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
        } else { toggleControls() }
    }
    @objc func toggleControls() { if popover.isShown { closeControls() } else { showControls() } }
    func showControls() {
        guard let button = statusItem.button else { return }
        menuTarget = TextDelivery.capture()
        model.refreshPermissions(); window.orderOut(nil); NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func closeControls() { popover.performClose(nil); finishEditing() }
    func popoverDidClose(_ notification: Notification) { finishEditing() }
    func resumeTarget(_ action: @escaping (TextDelivery.Target?) -> Void) {
        let target = menuTarget
        closeControls()
        // Restore only the app from which controls were opened. Delivery checks the
        // exact focused element again after processing; it never presses Return.
        target?.app.activate(options: [])
        Task { try? await Task.sleep(nanoseconds: 160_000_000); action(target) }
    }
    func menuRecording() {
        if model.phase == .recording { closeControls(); model.stopRecording(); return }
        resumeTarget { [weak self] target in self?.model.toggleRecording(target: target) }
    }
    func pasteLast() {
        guard !model.transcript.isEmpty, model.phase == .idle else { return }
        resumeTarget { [weak self] target in
            guard let self else { return }
            Task { self.model.status = await TextDelivery.deliver(self.model.transcript, target: target, mode: .paste, restoreClipboard: self.model.preferences.restoreClipboard) }
        }
    }
    func updateRecordingUI() {
        statusItem?.button?.image = NSImage(systemSymbolName: model.phase == .recording ? "mic.fill" : "waveform", accessibilityDescription: "Workbench Voice")
        statusItem?.button?.toolTip = "Workbench Voice · " + model.preferences.controlsShortcut.label
        if [.recording, .transcribing, .cleaning].contains(model.phase) {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame { overlay.setFrameOrigin(NSPoint(x: frame.midX - 190, y: frame.minY + 28)) }
            overlay.orderFrontRegardless()
        } else { overlay.orderOut(nil) }
    }
    @objc func showWindow() { closeControls(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showAbout() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Workbench Voice", .applicationVersion: "1.1.0", .credits: NSAttributedString(string: "Local dictation and text-to-speech.\nPowered by Parakeet, FluidAudio, and macOS voices.")]) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showControls(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown(); hotkeys.unregister() }
}

func runCLI(_ args: [String]) async -> Int32 {
    do {
        let engine = RecognitionEngine()
        switch args.first {
        case "--check-core":
            try CoreChecks.run(); try CleanupChecks.run()
        case "--check-input":
            try await MainActor.run { try InputChecks.run() }
        case "--check-cleanup":
            try CleanupChecks.run()
            let result = await CleanupEngine().clean(CleanupChecks.example, style: .natural)
            guard DictationCleanup.isFaithful(result.text, to: DictationCleanup.light(CleanupChecks.example)), result.text.contains("• Apples") else { throw VoiceError.message("Natural cleanup changed the checked example") }
            print("NATURAL_CHECK_OK: \(result.method)\n\(result.text)")
        case "--clean-text":
            guard args.count >= 2 else { throw VoiceError.message("Usage: --clean-text TEXT_FILE [Original|Light|Natural]") }
            let text = try String(contentsOfFile: args[1], encoding: .utf8)
            let result = await CleanupEngine().clean(text, style: args.count > 2 ? (CleanupStyle(rawValue: args[2]) ?? .light) : .light)
            print(result.text)
        case "--prepare-model":
            try await engine.prepare(); print("MODEL_READY: Parakeet v2")
        case "--transcribe":
            guard args.count == 2 else { throw VoiceError.message("Usage: LocalVoice --transcribe AUDIO_FILE") }
            print(try await engine.transcribe(URL(fileURLWithPath: args[1])))
        case "--self-test":
            try CoreChecks.run()
            let phrase = "The quick brown fox jumps over the lazy dog. Please bring the blue notebook to the meeting tomorrow morning."
            let audio = try AudioRenderer.render(text: phrase, voice: "Karen", rate: 165)
            defer { AudioRenderer.remove(audio) }
            let output = try await engine.transcribe(audio)
            let lower = output.lowercased()
            guard lower.contains("brown fox"), lower.contains("blue notebook"), lower.contains("tomorrow") else { throw VoiceError.message("Speech round-trip failed: \(output)") }
            print("ROUND_TRIP_OK: \(output)")
            let m4a = FileManager.default.temporaryDirectory.appendingPathComponent("LocalVoice-self-test.m4a")
            defer { try? FileManager.default.removeItem(at: m4a) }
            try AudioRenderer.export(audio, to: m4a)
            let file = try AVAudioFile(forReading: m4a)
            guard file.length > 0 else { throw VoiceError.message("M4A export was empty") }
            print("AUDIO_EXPORT_OK: \(Double(file.length) / file.processingFormat.sampleRate) seconds")
            let second = try await engine.transcribe(m4a)
            guard second.lowercased().contains("blue notebook") else { throw VoiceError.message("M4A recognition failed: \(second)") }
            print("M4A_TRANSCRIPTION_OK")
        default: throw VoiceError.message("Usage: LocalVoice [--prepare-model | --transcribe AUDIO_FILE | --check-core | --self-test]")
        }
        return 0
    } catch { fputs("Local Voice: \(error.localizedDescription)\n", stderr); return 1 }
}

if CommandLine.arguments.count > 1, CommandLine.arguments[1].hasPrefix("--") {
    Task { let code = await runCLI(Array(CommandLine.arguments.dropFirst())); exit(code) }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
