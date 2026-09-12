import SwiftUI

struct ReadingProviderView: View {
    @ObservedObject var model: AppModel
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Read with", selection: $model.readingProvider) {
                ForEach(ReadingProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if model.readingProvider == .speko {
                Text("Speko sends this reading to its cloud service and selected voice provider. Your Speko account may be charged. Your dictation engine is selected separately in Models.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    SecureField("Personal Speko API key", text: $key).textFieldStyle(.roundedBorder)
                    Button("Save key") { model.saveSpekoKey(key); key = "" }.disabled(key.isEmpty)
                    Button("Remove key") { model.removeSpekoKey(); key = "" }
                }
                HStack {
                    Text(model.keyNotice.isEmpty ? "Saved in this app’s Keychain. Never in your drafts or backups." : model.keyNotice)
                    Spacer()
                    Link("Speko account ↗", destination: URL(string: "https://platform.speko.ai")!)
                }.font(.caption).foregroundStyle(.secondary)
                Text("Automatic voice · balanced routing · up to 5,000 characters per reading")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(model.rendering).onDisappear { key = "" }
    }
}
