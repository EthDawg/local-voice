import AppIntents
import Foundation

/// One continuation per invocation: an action can never observe a previous draft.
@MainActor
final class DictationRequest {
    private(set) var id: UUID?
    private var completion: ((Result<String, Error>) -> Void)?
    func begin(id: UUID, completion: @escaping (Result<String, Error>) -> Void) throws {
        guard self.id == nil else { throw VoiceError.message("A Shortcuts recording is already running. Finish or cancel it first.") }
        self.id = id; self.completion = completion
    }
    func finish(id: UUID, result: Result<String, Error>) {
        guard self.id == id else { return }
        let callback = completion; self.id = nil; completion = nil
        callback?(result)
    }
    func cancel() {
        if let id { finish(id: id, result: .failure(CancellationError())) }
    }
}

/// Shortcuts owns Record Audio and its Stop button. This action never opens a microphone.
struct TranscribeWithWorkbench: AppIntent, ProgressReportingIntent {
    static var title: LocalizedStringResource = "Transcribe with Workbench"
    static var description = IntentDescription("Turn audio from Record Audio or a file into text on your Mac. Connect the result to Create Note, Copy to Clipboard, or any text action. Set up Voice’s speech model first.")
    static var openAppWhenRun = false
    @Parameter(title: "Audio", supportedTypeIdentifiers: ["public.audio"], inputConnectionBehavior: .connectToPreviousIntentResult)
    var audio: IntentFile
    static var parameterSummary: some ParameterSummary { Summary("Transcribe \(\.$audio)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let model = AppModel.intentModel else { throw VoiceError.message("Open Workbench Voice and finish preparing its speech model, then run the shortcut again.") }
        let id = UUID()
        let captureProgress = progress
        captureProgress.totalUnitCount = 1; captureProgress.isCancellable = true
        captureProgress.localizedDescription = "Transcribing on your Mac"
        captureProgress.cancellationHandler = { Task { @MainActor in model.cancelShortcut(id) } }
        defer { captureProgress.cancellationHandler = nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("LocalVoice-shortcut-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source: URL
        if let url = audio.fileURL { source = url }
        else {
            let data = audio.data
            guard !data.isEmpty, data.count <= 64 * 1024 * 1024 else { throw VoiceError.message("Choose an audio file smaller than 64 MB.") }
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            source = temporary.appendingPathComponent("input.audio")
            try data.write(to: source, options: .atomic)
        }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let text = try await model.transcribeForShortcut(source, id: id)
        captureProgress.completedUnitCount = 1
        return .result(value: text)
    }
}

struct VoiceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TranscribeWithWorkbench(), phrases: ["Transcribe audio with \(.applicationName)"],
                    shortTitle: "Transcribe with Workbench", systemImageName: "waveform")
    }
}
