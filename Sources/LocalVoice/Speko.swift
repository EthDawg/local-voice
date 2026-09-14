import Foundation
import Security

enum ReadingProvider: String, CaseIterable {
    case mac = "Mac voices"
    case speko = "Speko · online"
}

enum SpekoKeychain {
    static var service: String { (Bundle.main.bundleIdentifier ?? "com.ethdawg.localvoice.development") + ".speko" }
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"] }
    static var hasKey: Bool {
        var query = query
        query[kSecReturnAttributes as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    static func read() throws -> String {
        var query = query; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw VoiceError.message(status == errSecItemNotFound ? "Add your Speko API key in Read aloud first." : "Could not read the Speko key. Unlock Keychain and try again.")
        }
        return key
    }
    static func save(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count < 4096, !value.contains(where: { $0.isWhitespace }) else { throw VoiceError.message("Paste a valid Speko API key without spaces.") }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VoiceError.message("Could not save the key in Keychain. Your previous key was not removed.") }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VoiceError.message("Could not remove the Speko key. Unlock Keychain and try again.") }
    }
}

/// Never forward the key or reading to a redirected host.
private final class SpekoSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum SpekoRenderer {
    static let maximumCharacters = 5_000
    static let maximumAudioBytes = 64 * 1024 * 1024
    static func request(text: String, key: String) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maximumCharacters else {
            throw VoiceError.message("Keep each Speko reading between 1 and 5,000 characters.")
        }
        var request = URLRequest(url: URL(string: "https://router.speko.dev/v1/tts/speech")!)
        request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "routing": ["mode": "auto", "objective": "balanced"], "input": text,
            "audio": ["encoding": "pcm_s16le", "sample_rate_hz": 24000, "channels": 1]
        ])
        return request
    }
    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw VoiceError.message("Speko rejected this key or its access. Check your API key and account permissions.")
        case 402: throw VoiceError.message("Speko needs account credit or billing setup. Check your Speko account.")
        case 429: throw VoiceError.message("Speko is rate-limiting this request. Wait before trying again.")
        default: throw VoiceError.message("Speko could not generate audio (HTTP \(response.statusCode)). No automatic retry was made.")
        }
        guard response.mimeType == "application/octet-stream", response.expectedContentLength <= maximumAudioBytes else {
            throw VoiceError.message("Speko returned an unsupported audio response.")
        }
    }
    static func wav(_ pcm: Data) throws -> Data {
        guard !pcm.isEmpty, pcm.count.isMultiple(of: 2), pcm.count <= maximumAudioBytes else { throw VoiceError.message("Speko returned empty, incomplete or oversized audio.") }
        var data = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        number(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8)); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(24000)); number(UInt32(48000)); number(UInt16(2)); number(UInt16(16))
        data.append(Data("data".utf8)); number(UInt32(pcm.count)); data.append(pcm)
        return data
    }
    static func render(text: String, key: String) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: SpekoSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (stream, response) = try await session.bytes(for: request(text: text, key: key))
            guard let http = response as? HTTPURLResponse else { throw VoiceError.message("Speko returned an invalid response.") }
            try validate(http)
            var pcm = Data()
            for try await byte in stream {
                if pcm.count.isMultiple(of: 16384) { try Task.checkCancellation() }
                guard pcm.count < maximumAudioBytes else { throw VoiceError.message("Speko audio exceeded the reading size limit.") }
                pcm.append(byte)
            }
            try Task.checkCancellation()
            let data = try wav(pcm)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LocalVoice-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let output = folder.appendingPathComponent("speech.wav")
            do { try data.write(to: output, options: .atomic); return output }
            catch { try? FileManager.default.removeItem(at: folder); throw error }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw VoiceError.message("Could not reach Speko. Check your connection and try again. No automatic retry was made.")
        }
    }
}
