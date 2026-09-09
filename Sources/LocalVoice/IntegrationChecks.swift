import Foundation
import AVFoundation

enum IntegrationChecks {
    @MainActor static func run() throws {
        var count = 0
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw VoiceError.message("Integration check failed: " + name) }; count += 1
        }
        let request = DictationRequest(), first = UUID(), second = UUID()
        var results: [Result<String, Error>] = []
        try request.begin(id: first) { results.append($0) }
        do { try request.begin(id: second) { results.append($0) }; throw VoiceError.message("Concurrent capture accepted") }
        catch { try check(request.id == first, "concurrent invocation preserves original owner") }
        request.finish(id: second, result: .success("stale"))
        try check(results.isEmpty, "wrong invocation cannot complete")
        request.finish(id: first, result: .success("New capture"))
        request.finish(id: first, result: .success("duplicate"))
        try check(results.count == 1 && (try? results[0].get()) == "New capture", "exactly one owned result")
        try request.begin(id: second) { results.append($0) }
        request.cancel(); request.cancel()
        try check(results.count == 2 && request.id == nil, "cancellation releases owner exactly once")
        if case .failure(let error) = results[1] { try check(error is CancellationError, "cancel returns error, never old text") }
        let third = UUID()
        try request.begin(id: third) { results.append($0) }
        request.finish(id: second, result: .success("late previous result"))
        try check(request.id == third && results.count == 2, "late callback cannot affect next invocation")
        request.finish(id: third, result: .failure(VoiceError.message("Microphone unavailable")))
        try check(results.count == 3 && request.id == nil, "errors release request")
        let http = try SpekoRenderer.request(text: "Synthetic reading.", key: "synthetic-key")
        let body = try JSONSerialization.jsonObject(with: http.httpBody!) as! [String: Any]
        try check(http.url?.absoluteString == "https://router.speko.dev/v1/tts/speech" && http.httpMethod == "POST", "fixed HTTPS endpoint")
        try check(http.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key" && body["input"] as? String == "Synthetic reading.", "explicit reading and key only")
        try check(body["voice"] == nil && body["messages"] == nil && body["history"] == nil, "no provider-specific voice or transcript history")
        let next = try SpekoRenderer.request(text: "Synthetic reading.", key: "synthetic-key")
        try check(http.value(forHTTPHeaderField: "Idempotency-Key") != next.value(forHTTPHeaderField: "Idempotency-Key"), "distinct user actions have distinct request IDs")
        for text in ["", "   ", String(repeating: "a", count: 5001)] {
            var rejected = false
            do { _ = try SpekoRenderer.request(text: text, key: "synthetic-key") } catch { rejected = true }
            try check(rejected, "invalid length rejected before network")
        }
        for status in [301, 400, 401, 402, 403, 429, 500] {
            let response = HTTPURLResponse(url: http.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/octet-stream"])!
            var rejected = false; do { try SpekoRenderer.validate(response) } catch { rejected = true }
            try check(rejected, "HTTP \(status) rejected")
        }
        for type in ["text/html", "application/json", "audio/mpeg"] {
            let response = HTTPURLResponse(url: http.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!
            var rejected = false; do { try SpekoRenderer.validate(response) } catch { rejected = true }
            try check(rejected, "unexpected content rejected")
        }
        for pcm in [Data(), Data([1])] {
            var rejected = false; do { _ = try SpekoRenderer.wav(pcm) } catch { rejected = true }
            try check(rejected, "empty or partial sample rejected")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LocalVoice-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = folder.appendingPathComponent("synthetic.wav"), m4a = folder.appendingPathComponent("synthetic.m4a")
        try SpekoRenderer.wav(Data(repeating: 0, count: 48000)).write(to: wav)
        let file = try AVAudioFile(forReading: wav)
        try check(file.length == 24000 && file.processingFormat.sampleRate == 24000, "PCM wrapped as playable mono 24 kHz WAV")
        try AudioRenderer.export(wav, to: m4a)
        try check(try AVAudioFile(forReading: m4a).length > 0, "Speko format exports using existing M4A path")
        print("INTEGRATIONS_OK: \(count) checks (synthetic; no network or credentials)")
    }
}
