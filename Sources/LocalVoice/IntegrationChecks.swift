import Foundation

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
        print("SHORTCUTS_REQUESTS_OK: \(count) ownership, cancellation and error checks")
    }
}
