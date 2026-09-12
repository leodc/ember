import SwiftUI

struct RealtimeTestView: View {
    let definition: CallDefinition
    @Environment(CallController.self) private var callController
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = RealtimeTestController()

    var body: some View {
        @Bindable var callController = callController
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label("Realtime voice test", systemImage: "waveform")
                            .font(.largeTitle.bold())
                        Text("Speak as the receptionist. The agent uses your appointment details and selected agent language. No phone number is dialed.")
                            .foregroundStyle(Ember.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(definition.objective).font(.headline)
                            AgentLanguagePicker(language: $callController.definition.agentLanguage)
                                .disabled(controller.state.isActive)
                            if !definition.availability.isEmpty { Text(definition.availability) }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        status.accessibilityAddTraits(.updatesFrequently)
                        Text("Keep Ember in the foreground. Say hello to begin; you can interrupt the agent while it speaks.")
                            .font(.subheadline).foregroundStyle(Ember.secondary)
                        if !controller.transcripts.isEmpty {
                            Text("Agent transcript").font(.headline)
                            Text("Text may include speech you interrupted.").font(.caption).foregroundStyle(Ember.secondary)
                            ForEach(controller.transcripts) { item in
                                Text(item.text).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Color.clear.frame(height: 1).id("transcript-bottom")
                    }.padding(24)
                }
                .task(id: controller.transcripts.last?.text) {
                    guard !controller.transcripts.isEmpty else { return }
                    // Let the growing text lay out before moving to its bottom anchor.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .background(Ember.background)
            .safeAreaInset(edge: .bottom) {
                EmberFooter {
                    if controller.state.isActive {
                        Button("End voice test", role: .destructive) { controller.stop() }
                            .buttonStyle(.borderedProminent).frame(minHeight: 44)
                    } else {
                        VStack(spacing: 8) {
                            Text("Audio and appointment details are sent to OpenAI. API usage is billed separately.")
                                .font(.caption).foregroundStyle(Ember.secondary)
                            EmberPrimaryButton(title: "Start voice test", icon: "mic") {
                                var context = definition
                                context.userIdentity = settings.userIdentity
                                context.agentLanguage = callController.definition.agentLanguage
                                controller.start(definition: context, language: settings.language)
                            }.disabled(callController.definition.agentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { controller.stop(); dismiss() }
                }
            }
        }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, controller.state.isActive { controller.stop() }
        }
    }

    @ViewBuilder private var status: some View {
        switch controller.state {
        case .idle: Label("Ready to test", systemImage: "mic")
        case .connecting: HStack { ProgressView(); Text("Connecting to OpenAI…") }
        case .listening: Label("Agent listening", systemImage: "ear")
        case .thinking: Label("Agent thinking", systemImage: "ellipsis.bubble")
        case .speaking: Label("Agent speaking", systemImage: "waveform")
        case .ending: Label("Agent saying goodbye…", systemImage: "hand.wave")
        case .ended:
            if controller.endedByAgent {
                Label("The agent ended the session", systemImage: "checkmark.circle")
            } else {
                Label("Voice test ended", systemImage: "checkmark.circle")
            }
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }
}
