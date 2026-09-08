import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppModel: NSObject, ObservableObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    enum Phase: String { case idle, requesting, recording, transcribing }
    @Published var page = "dictate"
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
    @Published var autoPaste = UserDefaults.standard.bool(forKey: "autoPaste") {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var canRetry = false
    let engine = RecognitionEngine()
    let store = StateStore()
    private var loaded = false
    private var recorder: AVAudioRecorder?
    private var recordURL: URL?
    private var meter: Timer?
    private var player: AVAudioPlayer?
    private var playTimer: Timer?
    private var audioURL: URL?
    private var audioSignature = ""
    private var peakPower: Float = -160
    private var destination: NSRunningApplication?
    private var persistWork: DispatchWorkItem?
    var onPhaseChange: (() -> Void)?
    var voices: [String] = []

    override init() {
        super.init()
        do {
            let state = try store.load()
            transcript = state.draft; speechText = state.speechText; history = state.history
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

    func toggleRecording(fromShortcut: Bool = false) {
        if phase == .recording { stopRecording(); return }
        guard phase == .idle, ready, !rendering else { return }
        stopPlayback()
        let front = NSWorkspace.shared.frontmostApplication
        destination = fromShortcut && front?.processIdentifier != ProcessInfo.processInfo.processIdentifier ? front : nil
        Task { await startRecording() }
    }

    private func startRecording() async {
        phase = .requesting; error = nil; onPhaseChange?()
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .audio)
        default: granted = false
        }
        guard granted else {
            fail("Microphone access is off. Open Settings → Privacy & Security → Microphone and allow Local Voice."); return
        }
        do {
            if let old = recordURL { try? FileManager.default.removeItem(at: old) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("LocalVoice-recording-\(UUID().uuidString).wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let capture = try AVAudioRecorder(url: url, settings: settings)
            capture.delegate = self; capture.isMeteringEnabled = true
            guard capture.prepareToRecord(), capture.record() else { throw VoiceError.message("The microphone could not start. Check that an input device is connected.") }
            recorder = capture; recordURL = url; canRetry = false; elapsed = 0; level = 0; peakPower = -160
            phase = .recording; status = "Listening… press ⌃⌥Space to finish"; onPhaseChange?()
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
        guard phase == .recording else { return }
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
        phase = .transcribing; status = "Turning speech into text…"; error = nil; canRetry = false; onPhaseChange?()
        Task {
            do {
                let raw = try await engine.transcribe(url)
                let result = TextRules.apply(raw, replacements: replacements)
                guard !result.isEmpty else { throw VoiceError.message("No speech was recognised. Try speaking closer to the microphone.") }
                transcript = result
                history.insert(Transcript(text: result, seconds: duration), at: 0)
                history = Array(history.prefix(30)); persist()
                copyTranscript()
                accessibilityGranted = AXIsProcessTrusted()
                if autoPaste, accessibilityGranted, let destination,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier {
                    pasteToFrontApp()
                    status = "Paste requested in \(destination.localizedName ?? "your app"). Transcript also copied."
                } else {
                    status = self.destination == nil ? "Transcript ready and copied." : "Copied · press ⌘V where you want your words."
                }
                if temporary { try? FileManager.default.removeItem(at: url); recordURL = nil }
                phase = .idle; onPhaseChange?()
            } catch {
                canRetry = temporary; fail("Transcription failed. \(error.localizedDescription)")
            }
        }
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(transcript, forType: .string)
        status = "Copied to clipboard."
    }
    private func pasteToFrontApp() {
        // Only the app selected when the shortcut began may receive a paste. Never sends Return.
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
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
    func fail(_ text: String) { error = text; phase = .idle; status = "Needs attention"; onPhaseChange?() }
    func persist() {
        guard loaded else { return }
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        persistWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func saveNow() {
        guard loaded else { return }
        do { try store.save(SavedState(draft: transcript, speechText: speechText, history: history, replacements: replacements, voice: voice, rate: rate)) }
        catch { self.error = "Could not save this session. \(error.localizedDescription)" }
    }
    func shutdown() { cancelRecording(); stopPlayback(); saveNow(); AudioRenderer.remove(audioURL); if let recordURL { try? FileManager.default.removeItem(at: recordURL) } }
}
