import SwiftUI
import AppKit

private let ink = Color(red: 0.055, green: 0.075, blue: 0.085)
private let panelColor = Color(red: 0.09, green: 0.12, blue: 0.135)
private let mint = Color(red: 0.48, green: 0.89, blue: 0.73)

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("ON YOUR MAC", systemImage: "lock.shield").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(mint)
                    Spacer()
                    Text("⌃ ⌥ Space").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    Text("to dictate").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let error = model.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        Text(error).font(.system(size: 12)).textSelection(.enabled)
                        Spacer()
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
                    }.padding(14).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                Group {
                    switch model.page {
                    case "speak": speak
                    case "history": history
                    case "dictionary": DictionaryView(model: model)
                    case "settings": settings
                    default: dictate
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 8) {
                    Circle().fill(model.phase == .recording ? .red : mint).frame(width: 6, height: 6)
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Text("LOCAL VOICE  /  1.0").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.tertiary)
                }
            }.padding(32).background(ink)
        }
        .frame(minWidth: 900, minHeight: 680)
        .tint(mint).preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 24, weight: .medium)).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Voice").font(.system(size: 17, weight: .semibold))
                    Text("A little less typing.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 36).padding(.top, 12)
            nav("dictate", "Dictate", "mic")
            nav("speak", "Read aloud", "speaker.wave.2")
            Divider().padding(.vertical, 14)
            nav("history", "Recent transcripts", "clock")
            nav("dictionary", "Your dictionary", "text.book.closed")
            nav("settings", "Setup", "slider.horizontal.3")
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Circle().fill(model.ready ? mint : .orange).frame(width: 6, height: 6)
                    Text(model.ready ? "Local engine ready" : "Preparing engine").font(.system(size: 11, weight: .medium))
                }
                Text(model.ready ? "No account. No usage meter.\nYour words stay here." : model.modelMessage).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                if !model.ready && !model.preparing { Button("Retry model") { Task { await model.prepare() } }.font(.system(size: 11)) }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(panelColor, in: RoundedRectangle(cornerRadius: 12))
        }.padding(20).frame(width: 210).background(Color(red: 0.035, green: 0.05, blue: 0.06))
    }
    private func nav(_ page: String, _ title: String, _ icon: String) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 18); Text(title); Spacer() }
                .font(.system(size: 12, weight: model.page == page ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 12)
                .foregroundStyle(model.page == page ? mint : .secondary)
                .background(model.page == page ? mint.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 34, weight: .semibold)).tracking(-1)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }

    private var dictate: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Speak your mind.", "Turn a thought into text. Record here, or use the shortcut from any app.")
            HStack(spacing: 22) {
                Button { model.toggleRecording() } label: {
                    Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 27)).frame(width: 66, height: 66)
                        .foregroundStyle(ink).background(model.phase == .recording ? Color.red.opacity(0.9) : mint, in: Circle())
                }.buttonStyle(.plain).disabled(!model.ready || model.phase == .transcribing || model.phase == .requesting || model.rendering)
                    .accessibilityLabel(model.phase == .recording ? "Stop recording" : "Start recording")
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.phase == .recording ? "Listening to you" : model.phase == .transcribing ? "Finding your words…" : "Ready for your next thought")
                        .font(.system(size: 16, weight: .medium))
                    HStack(spacing: 10) {
                        if model.phase == .recording {
                            WaveBars(level: model.level).frame(width: 100, height: 22)
                            Text(time(model.elapsed)).monospacedDigit()
                            Button("Discard") { model.cancelRecording() }.buttonStyle(.plain).foregroundStyle(.secondary)
                        } else if model.phase == .transcribing || model.preparing {
                            ProgressView().controlSize(.small)
                            Text(model.preparing ? "Preparing the local model" : "Processing on your Mac")
                        } else { Text("Click the microphone or press ⌃⌥Space") }
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(panelColor, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("YOUR WORDS").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(TextRules.wordCount(model.transcript)) words").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                editor(text: $model.transcript, placeholder: "Your transcript will appear here.\nYou can edit it before copying or saving.", label: "Transcript")
            }.frame(maxHeight: .infinity)
            HStack(spacing: 12) {
                Button { model.copyTranscript() } label: { Label("Copy text", systemImage: "doc.on.doc") }.buttonStyle(PrimaryButton()).disabled(model.transcript.isEmpty)
                Button("Save text…") { model.exportTranscript() }.disabled(model.transcript.isEmpty)
                Spacer()
                if model.canRetry { Button("Retry transcription") { model.retryTranscription() } }
                Button { model.importAudio() } label: { Label("Import audio…", systemImage: "arrow.up.doc") }.disabled(!model.ready || model.phase != .idle)
            }.controlSize(.large)
            Text("Finished transcripts are copied automatically. Paste with ⌘V. Up to 5 minutes per recording.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var speak: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Give your words a voice.", "Paste something to hear it aloud, or save a reading to take with you.")
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VOICE").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    Picker("Voice", selection: $model.voice) { ForEach(model.voices, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 220)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("PACE").tracking(1.4); Spacer(); Text("\(Int(model.rate)) words/min").monospacedDigit() }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Slider(value: $model.rate, in: 100...300, step: 10).accessibilityLabel("Reading pace")
                }
            }.padding(20).background(panelColor, in: RoundedRectangle(cornerRadius: 14)).disabled(model.rendering)
            editor(text: $model.speechText, placeholder: "Paste an article, a draft, or a thought.\nLet your Mac do the reading.", label: "Text to read").disabled(model.rendering)
            HStack {
                Text("\(model.speechText.count.formatted()) / 50,000 characters").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if model.playing || model.paused { Text("\(time(model.playbackTime)) / \(time(model.audioDuration))").font(.system(size: 11, design: .monospaced)).foregroundStyle(mint) }
            }
            HStack(spacing: 12) {
                Button { model.listen() } label: { Label(model.rendering ? "Making audio…" : model.playing ? "Pause" : model.paused ? "Resume" : "Listen", systemImage: model.playing ? "pause.fill" : "play.fill") }
                    .buttonStyle(PrimaryButton()).disabled(model.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.rendering || model.phase != .idle || model.speechText.count > 50_000)
                if model.playing || model.paused { Button("Stop") { model.stopPlayback() } }
                Spacer()
                Button { model.saveAudio() } label: { Label("Save audio…", systemImage: "square.and.arrow.down") }.disabled(model.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.rendering || model.speechText.count > 50_000)
            }.controlSize(.large)
            Text("Uses installed macOS voices. Saved audio is M4A, ready for QuickTime, Music, or sharing.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Pick up a thought.", "Your last 30 transcripts, saved only on this Mac. Original recordings are discarded after transcription.")
            if model.history.isEmpty {
                VStack(spacing: 12) { Image(systemName: "clock").font(.system(size: 32)).foregroundStyle(mint); Text("Your first thought starts here."); Text("Record or import audio to create a transcript.").foregroundStyle(.secondary).font(.system(size: 12)) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.history) { item in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute()); Spacer(); Text("\(TextRules.wordCount(item.text)) words · \(time(item.seconds))") }.font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(item.text).font(.system(size: 13)).lineLimit(4).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    Button("Open transcript") { model.transcript = item.text; model.page = "dictate" }
                                    Button("Read aloud") { model.speechText = item.text; model.page = "speak" }
                                    Spacer()
                                    Button { model.removeTranscript(item) } label: { Image(systemName: "trash") }.accessibilityLabel("Remove transcript")
                                }.font(.system(size: 11)).buttonStyle(.borderless)
                            }.padding(18).background(panelColor, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("Ready, set, speak.", "A few simple controls. Everything else is taken care of.")
            VStack(alignment: .leading, spacing: 22) {
                settingRow("Speech model", model.modelMessage, "cpu") {
                    if model.preparing { ProgressView().controlSize(.small) }
                    else if model.ready { Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(mint) }
                    else { Button("Retry model") { Task { await model.prepare() } } }
                }
                Divider()
                settingRow("Microphone", "Local Voice records only when you start a recording.", "mic") { Button("Open settings") { model.openMicrophoneSettings() } }
                Divider()
                settingRow("Global shortcut", "Press once to record. Press again to finish. No need to hold it.", "keyboard") { Text("⌃ ⌥ Space").font(.system(size: 13, design: .monospaced)).foregroundStyle(mint) }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Paste into the app I started in", isOn: $model.autoPaste).font(.system(size: 13, weight: .medium))
                    Text("Optional. Requires macOS Accessibility permission. Local Voice pastes only if that app still has focus, and never presses Return. The clipboard keeps a copy.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    if model.accessibilityGranted { Label("Accessibility enabled", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(mint) }
                    else { Button("Enable typing into other apps…") { model.requestAccessibility() }.font(.system(size: 11)) }
                }
            }.padding(22).background(panelColor, in: RoundedRectangle(cornerRadius: 14))
            Text("Local by design").font(.system(size: 16, weight: .medium))
            Text("Audio is processed on your Mac. No account, API key, analytics, or subscription. The initial model download uses the internet; dictation and reading then work offline. Drafts, your dictionary, and recent transcripts are stored in Application Support/LocalVoice.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled)
            Spacer()
        }
    }
    private func settingRow<Accessory: View>(_ title: String, _ subtitle: String, _ icon: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(mint).frame(width: 20)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 13, weight: .medium)); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer(); accessory().font(.system(size: 11))
        }
    }
    private func editor(text: Binding<String>, placeholder: String, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(panelColor.opacity(0.6))
            if text.wrappedValue.isEmpty { Text(placeholder).font(.system(size: 15)).foregroundStyle(.tertiary).lineSpacing(7).padding(20).allowsHitTesting(false) }
            TextEditor(text: text).font(.system(size: 15)).lineSpacing(6).scrollContentBackground(.hidden).padding(14).accessibilityLabel(label)
        }.overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07))).frame(minHeight: 150, maxHeight: .infinity)
    }
}

struct DictionaryView: View {
    @ObservedObject var model: AppModel
    @State private var heard = ""
    @State private var written = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your words, your way.").font(.system(size: 34, weight: .semibold)).tracking(-1)
            Text("Correct names and specialist terms after transcription. Matches whole words and phrases, ignoring case.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) { Text("WHEN IT HEARS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary); TextField("e.g. git hub", text: $heard) }
                Image(systemName: "arrow.right").padding(.bottom, 7).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 8) { Text("WRITE THIS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary); TextField("e.g. GitHub", text: $written) }
                Button("Add") { model.addReplacement(heard: heard, written: written); heard = ""; written = "" }.disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty || written.trimmingCharacters(in: .whitespaces).isEmpty)
            }.textFieldStyle(.roundedBorder).controlSize(.large).padding(20).background(panelColor, in: RoundedRectangle(cornerRadius: 12))
            if model.replacements.isEmpty {
                Text("No corrections yet. Add a name or phrase above when you need one.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.replacements) { item in
                        HStack { Text(item.heard).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "arrow.right").foregroundStyle(mint); Text(item.written).frame(maxWidth: .infinity, alignment: .leading); Button { model.removeReplacement(item) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Remove correction") }
                            .font(.system(size: 13)).padding(16).background(panelColor, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 12)
            .foregroundStyle(ink).background(mint.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct WaveBars: View {
    let level: Double
    var body: some View { HStack(spacing: 3) { ForEach(0..<16) { index in RoundedRectangle(cornerRadius: 2).fill(mint).frame(width: 3, height: 3 + level * Double([10, 18, 12, 22, 15, 24, 16, 10][index % 8])) } }.animation(.easeOut(duration: 0.1), value: level) }
}
struct RecordingOverlay: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.phase == .recording ? "mic.fill" : "waveform").foregroundStyle(model.phase == .recording ? .red : mint)
            if model.phase == .recording { WaveBars(level: model.level); Text(time(model.elapsed)).monospacedDigit() }
            else { ProgressView().controlSize(.small); Text("Transcribing…") }
            Text("⌃⌥Space").foregroundStyle(.secondary)
        }.font(.system(size: 12, weight: .medium)).padding(18).background(.ultraThickMaterial, in: Capsule()).preferredColorScheme(.dark)
    }
}
func time(_ seconds: Double) -> String { String(format: "%d:%02d", max(0, Int(seconds)) / 60, max(0, Int(seconds)) % 60) }
