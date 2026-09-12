import Foundation

/// A value snapshot belongs to one operation, including permission and processing waits.
/// Preferences changed in the app apply to the next operation.
struct CaptureSettings {
    let preferences: VoicePreferences
    let cleanup: CleanupConfiguration
    let replacements: [Replacement]

    var outputLabel: String {
        switch preferences.cleanup {
        case .original: return "Original words"
        case .light: return "Light cleanup"
        case .natural: return cleanup.naturalProvider == .ollama ? "Natural · local model" : "Natural · Apple Intelligence"
        }
    }
}

enum CaptureInputPolicy {
    static func canStart(isPresenting: Bool, hasExternalMacTarget: Bool) -> Bool {
        !isPresenting || hasExternalMacTarget
    }
}
