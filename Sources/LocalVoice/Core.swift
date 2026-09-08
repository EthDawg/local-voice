import Foundation
import FluidAudio
import AVFoundation

enum VoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

struct Replacement: Codable, Identifiable, Equatable {
    var id = UUID()
    var heard: String
    var written: String
}

enum TextRules {
    static func apply(_ text: String, replacements: [Replacement]) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in replacements where !item.heard.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: item.heard) + "(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: NSRegularExpression.escapedTemplate(for: item.written))
        }
        return result
    }
    static func wordCount(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

struct Transcript: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
    var seconds: Double
}

struct SavedState: Codable {
    var draft = ""
    var speechText = ""
    var history: [Transcript] = []
    var replacements: [Replacement] = []
    var voice = "Karen"
    var rate = 180.0
}

struct StateStore {
    let url: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalVoice")) {
        url = directory.appendingPathComponent("state.json")
    }
    func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }
    func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

actor RecognitionEngine {
    private var manager: AsrManager?
    private var preparation: Task<AsrManager, Error>?

    func prepare() async throws {
        if manager != nil { return }
        if let preparation { manager = try await preparation.value; return }
        let task = Task<AsrManager, Error> {
            let models = try await AsrModels.downloadAndLoad(version: .v2)
            let engine = AsrManager(config: .default)
            try await engine.loadModels(models)
            return engine
        }
        preparation = task
        do { manager = try await task.value; preparation = nil }
        catch { preparation = nil; throw error }
    }

    func transcribe(_ url: URL) async throws -> String {
        try await prepare()
        guard let manager else { throw VoiceError.message("The speech model is not ready. Try preparing it again.") }
        var decoderState = try TdtDecoderState(decoderLayers: 2)
        let result = try await manager.transcribe(url, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AudioRenderer {
    static func render(text: String, voice: String, rate: Int) throws -> URL {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceError.message("Add some text first.") }
        guard text.count <= 50_000 else { throw VoiceError.message("Please keep each reading under 50,000 characters.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LocalVoice-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let input = folder.appendingPathComponent("input.txt")
        let output = folder.appendingPathComponent("speech.aiff")
        do {
            try text.write(to: input, atomically: true, encoding: .utf8)
            try run("/usr/bin/say", ["-v", voice, "-r", String(rate), "-f", input.path, "-o", output.path])
            try FileManager.default.removeItem(at: input)
            let file = try AVAudioFile(forReading: output)
            guard file.length > 0 else { throw VoiceError.message("This voice produced no audio. Choose another installed voice and try again.") }
            return output
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    static func export(_ source: URL, to destination: URL) throws {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: staged) }
        // Normalize the sample rate: compact macOS voices often emit 22.05 kHz,
        // whose AAC encoder cannot accept common music-oriented bitrates.
        try run("/usr/bin/afconvert", ["-f", "m4af", "-d", "aac@44100", "-b", "96000", source.path, staged.path])
        // Atomic write preserves an existing file if conversion fails.
        try Data(contentsOf: staged).write(to: destination, options: .atomic)
    }
    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VoiceError.message(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "The audio operation failed.")
        }
    }
    static func remove(_ url: URL?) {
        guard let url, url.deletingLastPathComponent().lastPathComponent.hasPrefix("LocalVoice-") else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
