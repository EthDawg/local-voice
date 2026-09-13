import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

struct MobileSpeechResult: Sendable {
    let original: String
    let audioURL: URL
    let seconds: Double
}

enum MobileSpeechAssetStatus: Equatable, Sendable { case unsupported, supported, downloading, installed }

/// One seam for Apple's model inventory. Tests exercise preparation without
/// downloading assets, opening the microphone, or touching a user's recovery.
@MainActor
protocol MobileSpeechAssetProviding {
    var isAvailable: Bool { get }
    func supportedLocales() async -> [Locale]
    func supportedLocale(equivalentTo locale: Locale) async -> Locale?
    func status(for locale: Locale) async -> MobileSpeechAssetStatus
    func install(for locale: Locale, progress: @escaping @MainActor (Double) -> Void) async throws
    func cancelInstallation()
}

@MainActor
final class AppleMobileSpeechAssets: MobileSpeechAssetProviding {
    private var request: AssetInstallationRequest?
    private var generation = UUID()
    var isAvailable: Bool { SpeechTranscriber.isAvailable }
    func supportedLocales() async -> [Locale] { await SpeechTranscriber.supportedLocales }
    func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }
    func status(for locale: Locale) async -> MobileSpeechAssetStatus {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return .installed
        case .downloading: return .downloading
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
    func install(for locale: Locale, progress: @escaping @MainActor (Double) -> Void) async throws {
        let token = UUID(); generation = token
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        // This API reserves the required asset locales itself. Do not manually
        // reserve a guessed variant or evict another language's reservation.
        guard let download = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        request = download
        let observer = Task { @MainActor in
            while !Task.isCancelled {
                guard self.generation == token else { return }
                progress(download.progress.fractionCompleted)
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
        defer { observer.cancel(); if generation == token { request = nil } }
        try await download.downloadAndInstall()
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
    }
    func cancelInstallation() {
        generation = UUID()
        request?.progress.cancel()
        request = nil
    }
}

struct MobileSpeechLanguage: Identifiable, Equatable {
    let id: String
    let name: String
}

enum MobileSpeechReadiness: Equatable { case checking, needsDownload, downloading, ready, unavailable, failed }

/// Owns a foreground capture or file transcription. Apple speech assets are the
/// only download; starting a capture never silently downloads or changes engines.
@MainActor
final class SpeechService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var phase = "Check speech availability"
    @Published private(set) var isRecording = false
    @Published private(set) var isWorking = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var error: String?
    @Published private(set) var isReady = false
    @Published private(set) var languageName: String
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var readiness = MobileSpeechReadiness.checking
    @Published private(set) var languages: [MobileSpeechLanguage] = []
    @Published private(set) var selectedLanguageID: String
    @Published private(set) var diagnosticDetail: String?
    @Published private(set) var microphoneDenied = false
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var recoveryAudioURL: URL?
    @Published private(set) var hasRecovery = false
    @Published private(set) var recoveryProblem: String?

    static let maximumRecordingSeconds: TimeInterval = 5 * 60
    static let maximumImportSeconds: TimeInterval = 30 * 60
    static let maximumImportBytes = 64_000_000

    private var requestedLocale: Locale
    private let assets: any MobileSpeechAssetProviding
    private let recoveryDirectory: URL?
    private let preferences: UserDefaults?
    private var generation = UUID()
    private var recorder: AVAudioRecorder?
    private var recordingTimer: Task<Void, Never>?
    private var operationTask: Task<MobileSpeechResult?, Never>?
    private var resultTask: Task<String, Error>?
    private var watchdog: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?
    private var ownsAudioSession = false
    private var subscriptions = Set<AnyCancellable>()

    init(locale: Locale = .current, assets: (any MobileSpeechAssetProviding)? = nil, recoveryDirectory: URL? = nil, preferences: UserDefaults? = .standard, observesInterruptions: Bool = true) {
        let selected = preferences?.string(forKey: "dictation.speechLanguage").map(Locale.init(identifier:)) ?? locale
        requestedLocale = selected
        selectedLanguageID = selected.identifier(.bcp47)
        languageName = Locale.current.localizedString(forIdentifier: selected.identifier) ?? selected.identifier
        self.assets = assets ?? AppleMobileSpeechAssets()
        self.recoveryDirectory = recoveryDirectory
        self.preferences = preferences
        super.init()
        refreshRecovery()
        guard observesInterruptions else { return }
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.interrupt("App moved to the background") }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    == AVAudioSession.InterruptionType.began.rawValue
                if began {
                    Task { @MainActor [weak self] in self?.interrupt("Audio was interrupted") }
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.interrupt("Audio services restarted") }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                let removed = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                if removed {
                    Task { @MainActor [weak self] in self?.interrupt("The audio device disconnected") }
                }
            }.store(in: &subscriptions)
    }

    /// Safe on first appearance: checks support and installed assets, without downloading.
    func refreshAvailability() async {
        guard !isWorking, !isRecording else { return }
        refreshRecovery()
        readiness = .checking
        _ = await perform(phase: "Checking speech availability", timeout: 30) { token in
            let locale = try await self.resolveLocale(token: token)
            let status = await self.assets.status(for: locale)
            try self.check(token)
            self.apply(status)
            return nil
        }
    }

    var canPrepare: Bool { !isWorking && !isRecording && [.needsDownload, .downloading, .failed].contains(readiness) }

    /// Choosing a language never downloads it or starts recording.
    func selectLanguage(_ identifier: String) async {
        guard !isWorking, !isRecording, languages.contains(where: { $0.id == identifier }) else { return }
        generation = UUID()
        requestedLocale = Locale(identifier: identifier)
        selectedLanguageID = identifier
        languageName = languages.first(where: { $0.id == identifier })?.name ?? identifier
        preferences?.set(identifier, forKey: "dictation.speechLanguage")
        isReady = false
        await refreshAvailability()
    }

    /// The UI must invoke this only after the user chooses to prepare/download speech.
    func prepare() async {
        guard !isWorking, !isRecording else { return }
        _ = await perform(phase: "Checking speech language", timeout: 15 * 60) { token in
            let locale = try await self.resolveLocale(token: token)
            let initial = await self.assets.status(for: locale)
            try self.check(token)
            self.apply(initial)
            guard initial != .unsupported else { throw ServiceError("Apple's speech assets are unavailable for \(self.languageName). Choose another supported language or check again later.") }
            if initial != .installed {
                self.phase = "Downloading speech language"
                self.readiness = .downloading
                try await self.assets.install(for: locale) { [weak self] value in
                    guard let self, self.generation == token, value.isFinite else { return }
                    self.downloadProgress = min(1, max(0, value))
                }
            }
            try self.check(token)
            let status = await self.assets.status(for: locale)
            try self.check(token)
            self.apply(status)
            guard status == .installed else { throw ServiceError("Apple has not finished installing \(self.languageName). Keep Workbench open and try the download again with an internet connection and available storage.") }
            return nil
        }
    }

    func start() async {
        guard !isWorking, !isRecording else { return }
        refreshRecovery()
        guard !hasRecovery else {
            error = "Transcribe or explicitly discard the previous recovery before recording again."
            return
        }
        _ = await perform(phase: "Checking microphone", timeout: nil) { token in
            _ = try await self.readyTranscriber(token: token)
            self.phase = "Requesting microphone access"
            let granted = await AVAudioApplication.requestRecordPermission()
            try self.check(token)
            self.microphoneDenied = !granted
            guard granted else { throw ServiceError("Allow microphone access in Settings to record. You can still import audio.") }
            self.phase = "Starting recording"
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            self.ownsAudioSession = true
            // PCM in CAF has recoverable data-length semantics if recording is
            // interrupted before its container is finalized (about 9.6 MB/5 min).
            let url = try self.audioDirectory().appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else {
                throw ServiceError("Recording could not start. Check the microphone and try again.")
            }
            // Persist the slot before starting the microphone. If persistence fails,
            // no new live capture can silently replace the previous recovery.
            try self.persistRecovery(url)
            recorder.delegate = self
            guard recorder.record(forDuration: Self.maximumRecordingSeconds) else {
                throw ServiceError("Recording could not start. Check the microphone and try again.")
            }
            self.recorder = recorder
            self.elapsed = 0
            self.inputLevel = 0
            self.isRecording = true
            self.phase = "Recording · up to 5 minutes"
            self.recordingTimer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self, self.generation == token, let current = self.recorder, self.isRecording else { return }
                    self.elapsed = min(current.currentTime, Self.maximumRecordingSeconds)
                    current.updateMeters()
                    self.inputLevel = min(1, max(0, (Double(current.averagePower(forChannel: 0)) + 50) / 50))
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            return nil
        }
    }

    func finish() async -> MobileSpeechResult? {
        guard isRecording, let url = stopRecorder() else { return nil }
        return await transcribeOwned(url: url)
    }

    func transcribe(url: URL) async -> MobileSpeechResult? {
        guard !isWorking, !isRecording else { return nil }
        refreshRecovery()
        if hasRecovery, recoveryAudioURL?.standardizedFileURL != url.standardizedFileURL {
            error = "Transcribe or explicitly discard the previous recovery before importing another recording."
            return nil
        }
        return await perform(phase: "Opening audio", timeout: 5 * 60) { token in
            let owned = try self.preserveInput(url)
            if !self.hasRecovery { try self.persistRecovery(owned) }
            return try await self.recognize(url: owned, token: token)
        }
    }

    /// Clears the recovery slot only after the UI confirms an explicit discard.
    /// Audio files themselves remain intact; this never deletes an import original.
    func discardRecovery() {
        guard !isWorking, !isRecording else { return }
        do {
            let marker = try audioDirectory().appendingPathComponent("recovery.json")
            if try markerAttributes(marker) != nil { try FileManager.default.removeItem(at: marker) }
            hasRecovery = false
            recoveryAudioURL = nil
            recoveryProblem = nil
            error = nil
            phase = isReady ? "Ready · on this device" : "Prepare speech to begin"
        } catch {
            self.error = "Recovery could not be cleared: \(error.localizedDescription)"
        }
    }

    /// The caller invokes this only after committing the transcript and audio to history.
    func markSaved(audioURL: URL) {
        guard !isWorking, !isRecording,
              recoveryAudioURL?.standardizedFileURL == audioURL.standardizedFileURL else { return }
        discardRecovery()
    }

    /// Cancels this invocation and keeps any captured/imported audio for an explicit retry.
    func cancel() {
        guard isWorking || isRecording else { return }
        cancelOperation(message: recoveryAudioURL == nil ? "Cancelled" : "Cancelled · audio kept for retry")
    }

    private func transcribeOwned(url: URL) async -> MobileSpeechResult? {
        await perform(phase: "Transcribing on this device", timeout: 5 * 60) { token in
            try await self.recognize(url: url, token: token)
        }
    }

    private func recognize(url: URL, token: UUID) async throws -> MobileSpeechResult {
        let duration = try audioDuration(url)
        elapsed = duration
        let module = try await readyTranscriber(token: token)
        try check(token)
        phase = "Transcribing on this device"
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        let results = Task<String, Error> {
            var text = ""
            for try await result in module.results {
                try Task.checkCancellation()
                text += String(result.text.characters)
                guard text.count <= 50_000, text.utf8.count <= 1_000_000 else {
                    throw ServiceError("The transcript exceeds 50,000 characters. Your audio is kept; import a shorter section.")
                }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        resultTask = results
        do {
            let file = try AVAudioFile(forReading: url)
            if let end = try await analyzer.analyzeSequence(from: file) {
                try check(token)
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let original = try await results.value
            try check(token)
            guard !original.isEmpty else { throw ServiceError("No speech was recognised. Your audio is kept for retry.") }
            phase = "Transcript ready"
            return MobileSpeechResult(original: original, audioURL: url, seconds: duration)
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private func resolveLocale(token: UUID) async throws -> Locale {
        guard assets.isAvailable else {
            isReady = false; readiness = .unavailable
            throw ServiceError("Apple's on-device speech model is unavailable on this device. Reading and text editing still work.")
        }
        let supported = await assets.supportedLocales()
        try check(token)
        languages = Dictionary(grouping: supported, by: { $0.identifier(.bcp47) }).keys.map { identifier in
            MobileSpeechLanguage(id: identifier, name: Locale.current.localizedString(forIdentifier: identifier) ?? identifier)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let equivalent = await assets.supportedLocale(equivalentTo: requestedLocale)
        try check(token)
        guard let locale = equivalent else {
            isReady = false; readiness = .unavailable
            throw ServiceError("On-device transcription does not support \(languageName) here. Choose one of Apple's available speech languages. Typing and the system keyboard still work.")
        }
        selectedLanguageID = locale.identifier(.bcp47)
        languageName = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        return locale
    }

    private func apply(_ status: MobileSpeechAssetStatus) {
        isReady = status == .installed
        switch status {
        case .installed: readiness = .ready; phase = "\(languageName) · ready on this device"
        case .supported: readiness = .needsDownload; phase = "Download \(languageName) once to record offline"
        case .downloading: readiness = .downloading; phase = "Apple is downloading \(languageName)"
        case .unsupported: readiness = .unavailable; phase = "Apple's speech assets are unavailable for \(languageName)"
        }
    }

    private func readyTranscriber(token: UUID) async throws -> SpeechTranscriber {
        let locale = try await resolveLocale(token: token)
        let status = await assets.status(for: locale)
        try check(token)
        apply(status)
        guard isReady else { throw ServiceError("Download the selected speech language first. This downloads Apple's model assets; your audio stays on this device.") }
        return SpeechTranscriber(locale: locale, preset: .transcription)
    }

    private func perform(phase: String, timeout: TimeInterval?, operation: @escaping @MainActor (UUID) async throws -> MobileSpeechResult?) async -> MobileSpeechResult? {
        guard !isWorking else { return nil }
        let token = UUID()
        generation = token
        isWorking = true
        error = nil
        diagnosticDetail = nil
        self.phase = phase
        let task = Task { @MainActor [weak self] () -> MobileSpeechResult? in
            guard let self else { return nil }
            defer { self.complete(token) }
            do {
                let result = try await operation(token)
                try self.check(token)
                return result
            } catch is CancellationError {
                return nil
            } catch {
                guard self.generation == token else { return nil }
                let failure = error as NSError
                self.diagnosticDetail = "Stage: \(self.phase)\nLanguage: \(self.selectedLanguageID)\nError: \(failure.domain) (\(failure.code))\niOS: \(UIDevice.current.systemVersion)"
                self.error = error.localizedDescription
                if !self.isReady, self.readiness != .unavailable { self.readiness = .failed }
                self.phase = self.recoveryAudioURL == nil ? "Unable to continue" : "Audio kept · retry when ready"
                return nil
            }
        }
        operationTask = task
        if let timeout {
            watchdog = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                guard let self, self.generation == token, self.isWorking else { return }
                self.cancelOperation(message: "Operation timed out · try again")
                self.error = "This operation took too long. Any saved audio is kept for retry."
                if !self.isReady { self.readiness = .failed }
            }
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                self?.cancel()
            }
        }
    }

    private func complete(_ token: UUID) {
        guard generation == token else { return }
        watchdog?.cancel()
        watchdog = nil
        downloadProgress = nil
        analyzer = nil
        resultTask = nil
        operationTask = nil
        isWorking = false
        if !isRecording { releaseAudioSession() }
    }

    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
    }

    private func interrupt(_ reason: String) {
        guard isWorking || isRecording else { return }
        cancelOperation(message: recoveryAudioURL == nil ? reason : "\(reason) · audio kept for retry")
    }

    private func cancelOperation(message: String) {
        generation = UUID()
        _ = stopRecorder()
        operationTask?.cancel()
        operationTask = nil
        resultTask?.cancel()
        resultTask = nil
        assets.cancelInstallation()
        watchdog?.cancel()
        watchdog = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        downloadProgress = nil
        isWorking = false
        error = nil
        diagnosticDetail = nil
        if !isReady, readiness == .checking || readiness == .downloading { readiness = .needsDownload }
        phase = message
        releaseAudioSession()
    }

    @discardableResult
    private func stopRecorder() -> URL? {
        recordingTimer?.cancel()
        recordingTimer = nil
        guard let recorder else { isRecording = false; return nil }
        let url = recorder.url
        elapsed = max(elapsed, min(recorder.currentTime, Self.maximumRecordingSeconds))
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil
        isRecording = false
        inputLevel = 0
        recoveryAudioURL = url
        releaseAudioSession()
        return url
    }

    private func releaseAudioSession() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func audioDirectory() throws -> URL {
        let directory: URL
        if let recoveryDirectory { directory = recoveryDirectory }
        else {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            directory = root.appendingPathComponent("Audio", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ServiceError("The audio folder is unavailable. Recovery has not been changed.")
        }
        return directory
    }

    private struct RecoveryMarker: Codable {
        let version: Int
        let filename: String
    }

    private func markerAttributes(_ marker: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: marker.path) }
        catch let failure as CocoaError where failure.code == .fileReadNoSuchFile || failure.code == .fileNoSuchFile {
            return nil
        }
    }

    private func recoveryURL(filename: String, directory: URL) throws -> URL {
        let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 36, UUID(uuidString: String(parts[0])) != nil,
              !parts[1].isEmpty, parts[1].count <= 10,
              parts[1].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            throw ServiceError("The recovery record has an invalid filename. It has been kept for review.")
        }
        return directory.appendingPathComponent(filename)
    }

    private func persistRecovery(_ url: URL) throws {
        let directory = try audioDirectory().standardizedFileURL
        let expected = try recoveryURL(filename: url.lastPathComponent, directory: directory)
        guard expected.standardizedFileURL == url.standardizedFileURL else {
            throw ServiceError("Only app-owned audio can be kept as recovery.")
        }
        let marker = directory.appendingPathComponent("recovery.json")
        guard try markerAttributes(marker) == nil else {
            throw ServiceError("An existing recovery must be saved or explicitly discarded first.")
        }
        let data = try JSONEncoder().encode(RecoveryMarker(version: 1, filename: url.lastPathComponent))
        try data.write(to: marker, options: .atomic)
        hasRecovery = true
        recoveryAudioURL = url
        recoveryProblem = nil
    }

    private func refreshRecovery() {
        guard !isWorking, !isRecording else { return }
        do {
            let directory = try audioDirectory()
            let marker = directory.appendingPathComponent("recovery.json")
            guard let attributes = try markerAttributes(marker) else {
                hasRecovery = false
                recoveryAudioURL = nil
                recoveryProblem = nil
                return
            }
            // An unreadable/malformed marker still occupies the recovery slot.
            // Never silently remove it and begin overwriting recovery state.
            hasRecovery = true
            recoveryAudioURL = nil
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 1024 else {
                throw ServiceError("The saved recovery record cannot be read safely. It has not been changed.")
            }
            let data = try Data(contentsOf: marker)
            guard data.count <= 1024 else { throw ServiceError("The saved recovery record is too large. It has not been changed.") }
            let record = try JSONDecoder().decode(RecoveryMarker.self, from: data)
            guard record.version == 1 else { throw ServiceError("This recovery was created by a different version of Workbench.") }
            let url = try recoveryURL(filename: record.filename, directory: directory)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ServiceError("The recovered audio file is missing or unavailable. The recovery record has been kept.")
            }
            recoveryAudioURL = url
            _ = try audioDuration(url)
            recoveryProblem = nil
        } catch {
            hasRecovery = true
            recoveryProblem = "Recovery needs attention: \(error.localizedDescription)"
        }
    }

    private func preserveInput(_ source: URL) throws -> URL {
        guard source.isFileURL else { throw ServiceError("Choose an audio file from Files.") }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        _ = try audioDuration(source)
        let directory = try audioDirectory().standardizedFileURL
        if source.standardizedFileURL.deletingLastPathComponent() == directory { return source }
        let suffix = source.pathExtension.lowercased()
        let safeSuffix = !suffix.isEmpty && suffix.count <= 10 && suffix.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
        let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(safeSuffix ? suffix : "audio")
        do {
            try copyBoundedAudio(from: source, to: target)
            _ = try audioDuration(target)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return target
    }

    private func copyBoundedAudio(from source: URL, to target: URL) throws {
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw ServiceError("The audio copy could not be created. Check available storage.")
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        var count = 0
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= Self.maximumImportBytes - count else {
                throw ServiceError("The audio file grew beyond the 64 MB limit. Export a smaller M4A file first.")
            }
            try output.write(contentsOf: chunk)
            count += chunk.count
        }
        try output.synchronize()
    }

    private func audioDuration(_ url: URL) throws -> TimeInterval {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes > 0, bytes <= Self.maximumImportBytes else {
            throw ServiceError("Choose a regular audio file no larger than 64 MB. Larger uncompressed recordings need to be exported as M4A first.")
        }
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        guard seconds.isFinite, seconds >= 0.2, seconds <= Self.maximumImportSeconds else {
            throw ServiceError("Audio must be between 0.2 seconds and 30 minutes long.")
        }
        return seconds
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identifier, self.isRecording else { return }
            _ = self.stopRecorder()
            self.phase = flag ? "Recording stopped · transcribe saved audio" : "Recording interrupted · audio kept for retry"
            if !flag { self.error = "Recording ended unexpectedly. Try the saved audio before recording again." }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identifier else { return }
            self.interrupt("Recording failed")
            self.error = "The audio could not be fully saved. The available recording is kept for retry."
        }
    }

    private struct ServiceError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
