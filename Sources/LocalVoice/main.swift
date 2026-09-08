import AppKit
import SwiftUI
import Carbon
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var overlay: NSPanel!
    var model: AppModel!
    var statusItem: NSStatusItem!
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        let root = NSHostingController(rootView: ContentView(model: model))
        window = NSWindow(contentViewController: root)
        window.title = "Local Voice"
        window.setContentSize(NSSize(width: 1060, height: 760))
        window.minSize = NSSize(width: 900, height: 700)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        overlay = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 70), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isFloatingPanel = true; overlay.level = .floating; overlay.isOpaque = false; overlay.backgroundColor = .clear
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.contentView = NSHostingView(rootView: RecordingOverlay(model: model))
        model.onPhaseChange = { [weak self] in self?.updateRecordingUI() }
        setupMenus(); registerShortcut(); showWindow()
    }
    private func setupMenus() {
        let main = NSMenu()
        let application = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Local Voice", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Local Voice", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Local Voice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = appMenu; main.addItem(application)
        let edit = NSMenuItem(); edit.title = "Edit"; let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu; main.addItem(edit)
        let windows = NSMenuItem(); windows.title = "Window"; let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Show Local Voice", action: #selector(showWindow), keyEquivalent: "0")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.submenu = windowMenu; main.addItem(windows); NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Local Voice")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Local Voice", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Start / stop dictation   ⌃⌥Space", action: #selector(toggleRecording), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }
    private func registerShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in delegate.toggleRecording() }
            return noErr
        }, 1, &event, context, &handler)
        let id = EventHotKeyID(signature: 0x4C564F49, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { model.error = "The shortcut ⌃⌥Space is already in use. Recording still works from this window or the menu bar." }
    }
    func updateRecordingUI() {
        statusItem.button?.image = NSImage(systemSymbolName: model.phase == .recording ? "mic.fill" : "waveform", accessibilityDescription: model.phase == .recording ? "Local Voice recording" : "Local Voice")
        if model.phase == .recording || model.phase == .transcribing {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let frame = screen?.visibleFrame { overlay.setFrameOrigin(NSPoint(x: frame.midX - 170, y: frame.minY + 28)) }
            overlay.orderFrontRegardless()
        } else { overlay.orderOut(nil) }
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleRecording() { model.toggleRecording(fromShortcut: true) }
    @objc func showAbout() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Local Voice", .applicationVersion: "1.0.0", .credits: NSAttributedString(string: "Local dictation and text-to-speech.\nPowered by Parakeet, FluidAudio, and macOS voices.")]) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown(); if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) } }
}

func runCLI(_ args: [String]) async -> Int32 {
    do {
        let engine = RecognitionEngine()
        switch args.first {
        case "--check-core":
            try CoreChecks.run()
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
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
