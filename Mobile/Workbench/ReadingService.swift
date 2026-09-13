import AVFoundation
import Combine
import Foundation
import MediaPlayer

/// Native iOS speech playback. This service does not invoke a network provider,
/// read the clipboard, or retain the user's text after stopping.
@MainActor
final class ReadingService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var error: String?
    @Published private(set) var currentRange: NSRange?
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var selectedVoiceID: String = ""

    var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.identifier.hasPrefix("com.apple.") && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { ($0.language, $0.name, $0.identifier) < ($1.language, $1.name, $1.identifier) }
    }

    private var synthesizer: AVSpeechSynthesizer?
    private var utteranceID: ObjectIdentifier?
    private var spokenUTF16Count = 0
    private var ownsAudioSession = false
    private var subscriptions = Set<AnyCancellable>()
    private var remoteIdentity: String?
    private var remoteTargets: [(command: MPRemoteCommand, target: Any, wasEnabled: Bool)] = []

    override init() {
        super.init()
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    == AVAudioSession.InterruptionType.began.rawValue
                if began {
                    Task { @MainActor [weak self] in self?.handleInterruption() }
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                let removed = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                if removed {
                    Task { @MainActor [weak self] in self?.handleInterruption() }
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isSpeaking else { return }
                    self.stop()
                    self.error = "Audio services restarted. Tap Read aloud to begin again."
                }
            }.store(in: &subscriptions)
    }

    func read(_ text: String) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Add some text to read aloud."; return }
        guard text.utf8.count <= 250_000 else { error = "Choose a shorter passage, up to 250 KB of text."; return }
        let voice: AVSpeechSynthesisVoice?
        if selectedVoiceID.isEmpty {
            voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
                ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        } else {
            voice = voices.first { $0.identifier == selectedVoiceID }
            guard voice != nil else { error = "This voice is no longer available. Choose another installed voice."; return }
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            ownsAudioSession = true
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = rate.isFinite
                ? min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
                : AVSpeechUtteranceDefaultSpeechRate
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.usesApplicationAudioSession = true
            synthesizer.delegate = self
            self.synthesizer = synthesizer
            utteranceID = ObjectIdentifier(utterance)
            spokenUTF16Count = text.utf16.count
            isSpeaking = true
            isPaused = false
            installRemoteControls()
            synthesizer.speak(utterance)
        } catch {
            stop()
            self.error = "Reading could not start: \(error.localizedDescription)"
        }
    }

    func pauseResume() {
        guard let synthesizer, isSpeaking else { return }
        if isPaused {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                ownsAudioSession = true
                guard synthesizer.continueSpeaking() else {
                    error = "Reading could not resume. Tap Stop, then Read aloud to begin again."
                    return
                }
                error = nil
                isPaused = false
                updateNowPlaying()
            } catch {
                self.error = "Reading could not resume: \(error.localizedDescription)"
            }
        } else if synthesizer.pauseSpeaking(at: .immediate) {
            isPaused = true
            updateNowPlaying()
            releaseAudioSession()
        }
    }

    func stop() {
        // Invalidate the utterance before stopping: delayed callbacks must not
        // reset a subsequent reading or release a newly owned audio session.
        utteranceID = nil
        synthesizer?.delegate = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        spokenUTF16Count = 0
        isSpeaking = false
        isPaused = false
        currentRange = nil
        error = nil
        removeRemoteControls()
        releaseAudioSession()
    }

    private func handleInterruption() {
        guard let synthesizer, isSpeaking, !isPaused else { return }
        if synthesizer.pauseSpeaking(at: .immediate) || synthesizer.isPaused {
            isPaused = true
            error = "Listening paused after an audio interruption. Resume when ready."
            updateNowPlaying()
            releaseAudioSession()
        } else {
            stop()
            error = "Listening stopped after an audio interruption. Tap Read aloud to begin again."
        }
    }

    private func releaseAudioSession() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func completed(_ identifier: ObjectIdentifier) {
        guard utteranceID == identifier else { return }
        stop()
    }

    private enum RemoteAction: Sendable { case play, pause, stop }

    private func installRemoteControls() {
        remoteIdentity = "workbench-reading-\(UUID().uuidString)"
        let commands = MPRemoteCommandCenter.shared()
        addRemoteTarget(commands.playCommand, action: .play)
        addRemoteTarget(commands.pauseCommand, action: .pause)
        addRemoteTarget(commands.stopCommand, action: .stop)
        updateNowPlaying()
    }

    private func addRemoteTarget(_ command: MPRemoteCommand, action: RemoteAction) {
        guard let identity = remoteIdentity else { return }
        let wasEnabled = command.isEnabled
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self, self.remoteIdentity == identity, self.isSpeaking else { return }
                switch action {
                case .play: if self.isPaused { self.pauseResume() }
                case .pause: if !self.isPaused { self.pauseResume() }
                case .stop: self.stop()
                }
            }
            return .success
        }
        remoteTargets.append((command, target, wasEnabled))
    }

    private func updateNowPlaying() {
        guard let identity = remoteIdentity else { return }
        let center = MPNowPlayingInfoCenter.default()
        let current = center.nowPlayingInfo?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String
        guard current == nil || current == identity else { return }
        // Never expose the draft, document title, or estimated progress on the Lock Screen.
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Workbench reading",
            MPNowPlayingInfoPropertyExternalContentIdentifier: identity,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0
        ]
    }

    private func removeRemoteControls() {
        let center = MPNowPlayingInfoCenter.default()
        let ownsMetadata = remoteIdentity != nil &&
            center.nowPlayingInfo?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String == remoteIdentity
        remoteIdentity = nil
        for item in remoteTargets {
            item.command.removeTarget(item.target)
            if ownsMetadata { item.command.isEnabled = item.wasEnabled }
        }
        remoteTargets.removeAll()
        if ownsMetadata { center.nowPlayingInfo = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.completed(identifier) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.completed(identifier) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier,
                  characterRange.location != NSNotFound,
                  characterRange.location <= self.spokenUTF16Count,
                  characterRange.length <= self.spokenUTF16Count - characterRange.location else { return }
            self.currentRange = characterRange
        }
    }
}
