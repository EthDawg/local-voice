import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppModel: NSObject, ObservableObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    static weak var intentModel: AppModel?
    let shortcutRequest = DictationRequest()
    func dictateForShortcut() async throws -> String {
        guard ready else { throw VoiceError.message("Open Voice and finish preparing the speech model, then run this shortcut again.") }
        guard phase == .idle, !rendering else { throw VoiceError.message("Voice is busy. Finish the current recording or reading first.") }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    try shortcutRequest.begin(id: id) { continuation.resume(with: $0) }
                    onCloseMenu?()
                    toggleRecording()
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.shortcutRequest.id == id else { return }
                self.shortcutRequest.cancel(); self.cancelRecording()
            }
        }
    }

    enum Phase: String { case idle, requesting, recording, transcribing, cleaning }
    @Published var preferences = VoicePreferences.load() {
        didSet {
            preferences.save()
            if oldValue.dictationShortcut != preferences.dictationShortcut || oldValue.controlsShortcut != preferences.controlsShortcut || oldValue.libraryShortcut != preferences.libraryShortcut { onShortcutsChanged?() }
        }
    }
    @Published var rawTranscript = ""
    @Published var cleanupMethod = ""
    @Published var editingShortcut: UInt32?
    @Published var shortcutRecordingMessage: String?
    @Published var previewingPanel = false
    @Published var shortcutFailures: [UInt32: String] = [:]
    @Published var quickTab = "Dictate"
    @Published var page = "dictate"
    @Published var libraryFocusToken = UUID()
    @Published var phase: Phase = .idle
    @Published var ready = false
    @Published var preparing = false
    @Published var modelMessage = "Preparing local speech…"
    @Published var status = "Ready when you are."
    @Published var error: String?
    @Published var transcript = "" { didSet { persist() } }
    @Published var speechText = "" { didSet { persist() } }
    @Published var history: [Transcript] = []
    @Published var replacements: [Replacement] = []
    @Published var voice = "Karen" { didSet { persist() } }
    @Published var rate = 180.0 { didSet { persist() } }
    @Published var elapsed = 0.0
    @Published var level = 0.0
    @Published var rendering = false
    @Published var playing = false
    @Published var paused = false
    @Published var audioDuration = 0.0
    @Published var playbackTime = 0.0
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var canRetry = false
    let engine = RecognitionEngine()
    let cleanupEngine = CleanupEngine()
    let store = StateStore()
    let library = DemoLibraryModel()
    private var loaded = false
    private var recorder: AVAudioRecorder?
    private var recordURL: URL?
    private var meter: Timer?
    private var player: AVAudioPlayer?
    private var playTimer: Timer?
    private var audioURL: URL?
    private var audioSignature = ""
    private var peakPower: Float = -160
    private var destination: TextDelivery.Target?
    private var recordingAttempt: UUID?
    private var permissionRequest: Task<Bool, Never>?
    private var persistWork: DispatchWorkItem?
    var onPhaseChange: (() -> Void)?
    var onShortcutsChanged: (() -> Void)?
    var onEditShortcut: ((UInt32) -> Void)?
    var onShowEditor: ((String) -> Void)?
    var onMenuRecording: (() -> Void)?
    var onCloseMenu: (() -> Void)?
    var onPasteLast: (() -> Void)?
    var onPasteTranscript: ((String) -> Void)?
    var onCancelShortcut: (() -> Void)?
    var onResetShortcuts: (() -> Void)?
    var onResetPanel: (() -> Void)?
    var voices: [String] = []

    override init() {
        super.init()
        Self.intentModel = self
        do {
            let state = try store.load()
            transcript = state.draft; speechText = state.speechText; history = state.history
            rawTranscript = state.rawDraft ?? state.draft
            replacements = state.replacements; voice = state.voice; rate = state.rate
        } catch {
            let backup = store.url.deletingLastPathComponent().appendingPathComponent("state-unreadable-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: store.url, to: backup)
                self.error = "Your saved session could not be opened. A recovery copy was preserved as \(backup.lastPathComponent) in Application Support/LocalVoice."
            } catch {
                self.error = "Your saved session could not be opened or backed up. Automatic saving is disabled to protect the original file."
                return
            }
        }
        voices = NSSpeechSynthesizer.availableVoices.compactMap { id in
            let info = NSSpeechSynthesizer.attributes(forVoice: id)
            guard let locale = info[.localeIdentifier] as? String, locale.hasPrefix("en"), let name = info[.name] as? String else { return nil }
            return name
        }.sorted()
        let preferred = ["Karen", "Samantha", "Daniel", "Moira", "Rishi", "Tessa"]
        voices = preferred.filter { voices.contains($0) } + voices.filter { !preferred.contains($0) }
        if !voices.contains(voice), let first = voices.first { voice = first }
        loaded = true
        Task { await prepare() }
    }

    func prepare() async {
        guard !preparing, !ready else { return }
        preparing = true; modelMessage = "Preparing Parakeet · first setup may take a few minutes"
        do { try await engine.prepare(); ready = true; modelMessage = "Parakeet · English · on your Mac" }
        catch { modelMessage = "Speech model needs attention"; self.error = "Could not prepare the speech model. Check your connection and click Retry model. \(error.localizedDescription)" }
        preparing = false
    }

    func toggleRecording(fromShortcut: Bool = false, target: TextDelivery.Target? = nil) {
        if phase == .recording { stopRecording(); return }
        guard phase == .idle, ready, !rendering else { return }
        previewingPanel = false
        stopPlayback()
        let attempt = UUID(); recordingAttempt = attempt
        destination = target ?? (fromShortcut ? TextDelivery.capture() : nil)
        phase = .requesting
        Task { await startRecording(attempt) }
    }
    func shortcutChanged(down: Bool) {
        if preferences.capture == .toggle { if down { toggleRecording(fromShortcut: true) }; return }
        if down { if phase == .idle { toggleRecording(fromShortcut: true) } }
        else if phase == .recording { stopRecording() }
        else if phase == .requesting { cancelRecording() }
    }

    private func startRecording(_ attempt: UUID) async {
        phase = .requesting; error = nil; onPhaseChange?()
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined:
            status = "Allow Microphone access in the macOS prompt."
            if permissionRequest == nil { permissionRequest = Task { await AVCaptureDevice.requestAccess(for: .audio) } }
            granted = await permissionRequest!.value; permissionRequest = nil
        default: granted = false
        }
        guard recordingAttempt == attempt else { return }
        guard granted else {
            fail("Microphone access is off. Open Settings → Privacy & Security → Microphone and allow Workbench Voice."); return
        }
        do {
            if let old = recordURL { try? FileManager.default.removeItem(at: old) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LocalVoice-recording-\(UUID().uuidString).wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let capture = try AVAudioRecorder(url: url, settings: settings)
            capture.delegate = self; capture.isMeteringEnabled = true
            guard capture.prepareToRecord(), capture.record() else { throw VoiceError.message("The microphone could not start. Check that an input device is connected.") }
            recorder = capture; recordURL = url; canRetry = false; elapsed = 0; level = 0; peakPower = -160
            phase = .recording; status = shortcutRequest.id != nil ? "Listening for Shortcuts… choose Finish to return text" : preferences.capture == .toggle ? "Listening… press \(preferences.dictationShortcut.label) to finish" : "Listening… release the shortcut to finish"; onPhaseChange?()
            meter = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let recorder = self.recorder else { return }
                    recorder.updateMeters(); self.elapsed = recorder.currentTime
                    self.peakPower = max(self.peakPower, recorder.peakPower(forChannel: 0))
                    self.level = max(0, min(1, Double(recorder.averagePower(forChannel: 0) + 55) / 55))
                    if self.elapsed >= 300 { self.stopRecording() }
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    func stopRecording() {
        guard phase == .recording, let url = recordURL else { return }
        let duration = recorder?.currentTime ?? elapsed
        recorder?.stop(); recorder = nil; meter?.invalidate(); meter = nil; level = 0
        guard duration >= 0.35, peakPower > -55 else {
            try? FileManager.default.removeItem(at: url); recordURL = nil
            fail("No clear speech was captured. Check your microphone and try again."); return
        }
        transcribe(url, duration: duration, temporary: true)
    }

    func cancelRecording() {
        if phase == .requesting {
            shortcutRequest.cancel(); recordingAttempt = nil; phase = .idle; status = "Capture cancelled. Use the shortcut again when microphone permission is ready."; onPhaseChange?(); return
        }
        guard phase == .recording else { return }
        shortcutRequest.cancel()
        recordingAttempt = nil
        recorder?.stop(); recorder = nil; meter?.invalidate(); meter = nil
        if let url = recordURL { try? FileManager.default.removeItem(at: url) }; recordURL = nil
        phase = .idle; level = 0; status = "Recording discarded."; onPhaseChange?()
    }

    func importAudio() {
        guard phase == .idle, ready else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        panel.message = "Choose an audio file up to 30 minutes. It stays on your Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAudio(url)
    }
    func importAudio(_ url: URL) {
        guard phase == .idle, ready else { return }
        do {
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            guard duration > 0, duration <= 1800 else { throw VoiceError.message("Choose an audio file between 1 second and 30 minutes long.") }
            destination = nil; transcribe(url, duration: duration, temporary: false)
        } catch { fail("Could not read this audio file. \(error.localizedDescription)") }
    }
    func retryTranscription() {
        guard phase == .idle, let url = recordURL else { return }
        transcribe(url, duration: elapsed, temporary: true)
    }

    private func transcribe(_ url: URL, duration: Double, temporary: Bool) {
        let shortcutID = shortcutRequest.id
        phase = .transcribing; status = "Turning speech into text…"; error = nil; canRetry = false; onPhaseChange?()
        Task {
            do {
                let raw = try await engine.transcribe(url)
                if let shortcutID, shortcutRequest.id != shortcutID { throw CancellationError() }
                phase = .cleaning; status = "Tidying your words…"; onPhaseChange?()
                let cleaned = await cleanupEngine.clean(raw, style: preferences.cleanup)
                if let shortcutID, shortcutRequest.id != shortcutID { throw CancellationError() }
                let result = TextRules.apply(cleaned.text, replacements: replacements)
                guard !result.isEmpty else { throw VoiceError.message("No speech was recognised. Try speaking closer to the microphone.") }
                rawTranscript = raw; transcript = result
                cleanupMethod = cleaned.method
                history = TranscriptHistory.adding(Transcript(text: result, seconds: duration, rawText: raw, cleanupMethod: cleaned.method), to: history)
                // Commit the capture before focus restoration or clipboard delivery can suspend this task.
                saveNow()
                accessibilityGranted = AXIsProcessTrusted()
                if let shortcutID {
                    status = "Transcript returned to Shortcuts."
                    shortcutRequest.finish(id: shortcutID, result: .success(result))
                } else {
                    status = await TextDelivery.deliver(result, target: destination, mode: preferences.delivery, restoreClipboard: preferences.restoreClipboard)
                }
                if temporary { try? FileManager.default.removeItem(at: url); recordURL = nil }
                phase = .idle; onPhaseChange?()
            } catch {
                if error is CancellationError {
                    if temporary { try? FileManager.default.removeItem(at: url); recordURL = nil }
                    phase = .idle; status = "Shortcuts capture cancelled."; onPhaseChange?(); return
                }
                canRetry = temporary && shortcutID == nil; fail("Transcription failed. \(error.localizedDescription)")
            }
        }
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        TextDelivery.copy(transcript)
        status = "Copied to clipboard."
    }
    func showLibrary() { page = "library"; onShowEditor?("library"); libraryFocusToken = UUID() }
    func savePrompt(_ text: String) { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; showLibrary(); library.newPrompt(text) }
    func copyCapture(_ item: Transcript) { TextDelivery.copy(item.text); status = "Transcript copied." }
    func showPanelPreview() {
        guard phase == .idle else { return }
        previewingPanel = true; onPhaseChange?()
    }
    func closePanelPreview() { previewingPanel = false; onPhaseChange?() }
    func cleanCurrentDraft() {
        guard phase == .idle, !transcript.isEmpty else { return }
        let original = transcript
        phase = .cleaning; error = nil
        Task {
            let cleaned = await cleanupEngine.clean(original, style: preferences.cleanup)
            rawTranscript = original; transcript = TextRules.apply(cleaned.text, replacements: replacements)
            cleanupMethod = cleaned.method; phase = .idle; status = cleaned.method + " · original retained"; persist()
        }
    }
    func openTranscript(_ item: Transcript) {
        transcript = item.text; rawTranscript = item.rawText ?? item.text; cleanupMethod = item.cleanupMethod ?? "Original"; page = "dictate"; persist()
    }
    func useOriginal() { transcript = rawTranscript; cleanupMethod = "Original restored"; status = "Original transcript restored."; persist() }
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityGranted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    func refreshPermissions() { accessibilityGranted = AXIsProcessTrusted() }
    func openMicrophoneSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
    func exportTranscript() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Transcript.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try transcript.write(to: url, atomically: true, encoding: .utf8); status = "Transcript saved." }
        catch { fail(error.localizedDescription) }
    }

    private var signature: String { "\(voice)|\(Int(rate))|\(speechText)" }
    func listen() {
        guard !rendering, phase == .idle else { return }
        if playing { player?.pause(); playing = false; paused = true; return }
        if paused, signature == audioSignature { player?.play(); playing = true; paused = false; return }
        stopPlayback()
        Task {
            do {
                let url = try await generateAudio()
                player = try AVAudioPlayer(contentsOf: url); player?.delegate = self
                guard player?.play() == true else { throw VoiceError.message("Audio could not play. Check your Mac's audio output.") }
                playing = true; audioDuration = player?.duration ?? 0; status = "Reading aloud."
                playTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.playbackTime = self?.player?.currentTime ?? 0 }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func generateAudio() async throws -> URL {
        if let audioURL, signature == audioSignature { return audioURL }
        rendering = true; error = nil
        let text = speechText, selectedVoice = voice, selectedRate = Int(rate), originalSignature = signature
        defer { rendering = false }
        let url = try await Task.detached(priority: .userInitiated) { try AudioRenderer.render(text: text, voice: selectedVoice, rate: selectedRate) }.value
        AudioRenderer.remove(audioURL); audioURL = url; audioSignature = originalSignature
        return url
    }
    func saveAudio() {
        guard !rendering, !speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Audio]; panel.nameFieldStringValue = "Reading.m4a"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                let url = try await generateAudio()
                rendering = true
                try await Task.detached { try AudioRenderer.export(url, to: destination) }.value
                rendering = false; status = "Audio saved to \(destination.lastPathComponent)."
            } catch { rendering = false; self.error = error.localizedDescription }
        }
    }
    func stopPlayback() {
        player?.stop(); player = nil; playing = false; paused = false; playbackTime = 0
        playTimer?.invalidate(); playTimer = nil
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stopPlayback(); self.status = flag ? "Finished reading." : "Playback interrupted." }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.cancelRecording(); self.fail(error?.localizedDescription ?? "Recording was interrupted. Please try again.") }
    }
    func addReplacement(heard: String, written: String) {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines), written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !written.isEmpty else { return }
        replacements.append(Replacement(heard: heard, written: written)); persist()
    }
    func removeReplacement(_ item: Replacement) { replacements.removeAll { $0.id == item.id }; persist() }
    func removeTranscript(_ item: Transcript) { history.removeAll { $0.id == item.id }; persist() }
    func fail(_ text: String) { if let id = shortcutRequest.id { shortcutRequest.finish(id: id, result: .failure(VoiceError.message(text))) }; error = text; phase = .idle; status = "Needs attention"; onPhaseChange?() }
    func persist() {
        guard loaded else { return }
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        persistWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func saveNow() {
        guard loaded else { return }
        do { try store.save(SavedState(draft: transcript, speechText: speechText, history: history, replacements: replacements, voice: voice, rate: rate, rawDraft: rawTranscript)) }
        catch { self.error = "Could not save this session. \(error.localizedDescription)" }
    }
    func shutdown() { shortcutRequest.cancel(); cancelRecording(); stopPlayback(); saveNow(); AudioRenderer.remove(audioURL); if let recordURL { try? FileManager.default.removeItem(at: recordURL) } }
}
