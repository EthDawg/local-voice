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

struct DictateWithWorkbench: AppIntent {
    static var title: LocalizedStringResource = "Dictate with Workbench"
    static var description = IntentDescription("Record on your Mac, choose Finish, and return the transcript to the next action. Does not copy or paste. Set up the speech model in Voice first.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let model = AppModel.intentModel else {
            throw VoiceError.message("Open Workbench Voice and let it finish starting, then run the shortcut again.")
        }
        return .result(value: try await model.dictateForShortcut())
    }
}

struct VoiceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DictateWithWorkbench(), phrases: ["Dictate with \(.applicationName)"],
                    shortTitle: "Dictate with Workbench", systemImageName: "mic")
    }
}
