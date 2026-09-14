import SwiftUI

@MainActor
struct RealtimeTestView: View {
    let definition: CallDefinition
    let phoneCall: Bool
    @Environment(CallController.self) private var callController
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var controller: RealtimeTestController
    @State private var followTranscript = true

    init(definition: CallDefinition, controller: RealtimeTestController? = nil, phoneCall: Bool = false) {
        self.definition = definition
        self.phoneCall = phoneCall
        _controller = State(initialValue: controller ?? (phoneCall
            ? RealtimeTestController(makeService: { BridgedCallService() }, permission: { true }, connectionTimeout: .seconds(100))
            : RealtimeTestController()))
    }

    private var hasConversation: Bool { controller.state.isActive || !controller.transcripts.isEmpty }

    var body: some View {
        @Bindable var callController = callController
        NavigationStack {
            VStack(spacing: 0) {
                if hasConversation && !dynamicTypeSize.isAccessibilitySize {
                    conversationHeader
                    Divider().opacity(0.4)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if hasConversation && dynamicTypeSize.isAccessibilitySize {
                                conversationHeader
                            }
                            if !hasConversation {
                                Text(copy("Rehearse the conversation", "Let Ember make the call")).font(.largeTitle.bold())
                                Text(copy("You play the receptionist; Ember represents you. Say hello, ask a question, or offer a different time. No real call is made.", "Ember will call this number and speak for you. Your iPhone microphone and speaker are not used. Keep the app in the foreground."))
                                    .foregroundStyle(Ember.secondary)
                                if phoneCall { Text(PhoneNumberInput.display(definition.phoneNumber)).font(.headline) }
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(definition.objective).font(.headline)
                                    AgentLanguagePicker(language: $callController.definition.agentLanguage)
                                    Text(definition.availability)
                                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                                Label("You can answer Ember’s questions or send a new instruction at any time.", systemImage: "text.bubble")
                                    .font(.subheadline).foregroundStyle(Ember.secondary)
                                status
                            } else {
                                DisclosureGroup("Call details") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(definition.objective)
                                        Text(definition.availability)
                                        Text(LocalizedStringKey(callController.definition.agentLanguage))
                                        Text("Transcripts may be delayed or inaccurate and may include interrupted speech.")
                                            .font(.caption).foregroundStyle(Ember.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                                }.font(.subheadline).foregroundStyle(Ember.secondary)
                            }
                            if controller.transcripts.isEmpty && controller.state.isActive {
                                VStack(spacing: 12) {
                                    Image(systemName: "waveform").font(.largeTitle).foregroundStyle(Ember.orange)
                                    Text("The conversation will appear here").font(.headline)
                                    Text(copy("Say hello as the receptionist to begin.", "Ember waits for the person who answers to say hello.")).font(.subheadline).foregroundStyle(Ember.secondary)
                                }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 56)
                            }
                            ForEach(controller.transcripts) { item in
                                TranscriptBubble(item: item)
                            }
                            if let audio = controller.bridgeDiagnostics {
                                DisclosureGroup("Audio diagnostics") {
                                    VStack(spacing: 10) {
                                        LabeledContent("Telnyx audio received", value: audio.telephone.receivedBlocks.formatted())
                                        LabeledContent("Audio supplied to OpenAI", value: audio.toAgent.readBlocks.formatted())
                                        LabeledContent("OpenAI audio received", value: audio.realtime.receivedBlocks.formatted())
                                        LabeledContent("Audio supplied to Telnyx", value: audio.toRecipient.readBlocks.formatted())
                                        LabeledContent("Recipient signal blocks", value: audio.telephone.nonSilentReceivedBlocks.formatted())
                                        LabeledContent("Agent signal blocks", value: audio.realtime.nonSilentReceivedBlocks.formatted())
                                        LabeledContent("Audio callback errors", value: (audio.telephone.callbackErrors + audio.realtime.callbackErrors).formatted())
                                        LabeledContent("Audio queue overflows", value: (audio.toAgent.overflows + audio.toRecipient.overflows).formatted())
                                    }.font(.caption).padding(.top, 10)
                                }.font(.subheadline)
                            }
                            if !controller.state.isActive && hasConversation {
                                VStack(alignment: .leading, spacing: 10) {
                                    status.font(.headline)
                                    if case .failed(let message) = controller.state {
                                        Text(message).font(.subheadline).foregroundStyle(Ember.secondary)
                                    }
                                    Text(copy("This was a rehearsal. No appointment was booked by the app.", "The call has ended. A booking is confirmed only if the recipient explicitly confirmed it."))
                                        .font(.subheadline).foregroundStyle(Ember.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                                    .background(Ember.peach.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
                            }
                            Color.clear.frame(height: 1).id("transcript-bottom")
                        }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
                        if followTranscript, !controller.transcripts.isEmpty { followTranscript = false }
                    })
                    .task {
                        // Token deltas must not start a new scroll/layout task each frame.
                        // Keep one bounded follower and leave the hidden list still during ask_user.
                        var lastFollowed: [RealtimeTestController.Transcript] = []
                        var lastFollowedState = controller.state
                        var settleLayout = false
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(200)) }
                            catch { return }
                            guard followTranscript, controller.pendingQuestion == nil,
                                  !controller.transcripts.isEmpty else { continue }
                            let changed = controller.transcripts != lastFollowed || controller.state != lastFollowedState
                            guard changed || settleLayout else { continue }
                            // A bounded second pass accommodates multiline text layout after insertion.
                            settleLayout = changed
                            lastFollowed = controller.transcripts
                            lastFollowedState = controller.state
                            proxy.scrollTo("transcript-bottom", anchor: .bottom)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !followTranscript {
                            Button {
                                followTranscript = true
                                withAnimation { proxy.scrollTo("transcript-bottom", anchor: .bottom) }
                            } label: {
                                Label("Latest messages", systemImage: "arrow.down")
                                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 12)
                            }
                            .buttonStyle(.plain).foregroundStyle(.white)
                            .background(Ember.ink, in: Capsule()).padding(16)
                            .accessibilityIdentifier("transcript-latest")
                        }
                    }
                }
            }
            .background(Ember.background).foregroundStyle(Ember.ink)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if controller.state.isActive {
                    HStack(alignment: .top, spacing: 10) {
                        InstructionComposer(controller: controller)
                        Button(role: .destructive) { controller.stop() } label: {
                            Image(systemName: "phone.down.fill").font(.body.weight(.semibold))
                                .frame(width: 54, height: 54)
                                .background(Color.red.opacity(0.08), in: Circle())
                        }.buttonStyle(.plain).foregroundStyle(.red)
                            .accessibilityLabel(copy("End voice test", "End phone call")).accessibilityIdentifier("live-end-session")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity).background(Ember.background)
                    .overlay(alignment: .top) { Divider().opacity(0.4) }
                } else {
                    EmberFooter {
                        VStack(spacing: 10) {
                            SessionActionButton(title: phoneCall ? "Call with Ember" : (hasConversation ? "Start a new rehearsal" : "Start rehearsal")) {
                                var context = definition
                                context.userIdentity = settings.userIdentity
                                context.agentLanguage = callController.definition.agentLanguage
                                followTranscript = true
                                controller.start(definition: context, language: settings.language)
                            }.disabled(callController.definition.agentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (phoneCall && !definition.canPlaceCall))
                            Text(copy("Audio and appointment details are sent to OpenAI. API usage is billed separately.", "This places a real call. Telnyx and OpenAI charges apply. Call audio and appointment details are sent to OpenAI."))
                                .font(.caption).foregroundStyle(Ember.secondary)
                        }
                    }
                }
            }
            .navigationTitle(copy("Voice rehearsal", "Phone call with Ember"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { controller.stop(); dismiss() } label: {
                        Text(controller.state.isActive ? copy("End rehearsal", "End phone call") : LocalizedStringKey("Done"))
                    }
                }
            }
        }
        .tint(Ember.ink).preferredColorScheme(.light)
        .sheet(item: Binding(get: { controller.pendingQuestion }, set: { _ in })) { request in
            AskUserView(request: request, sending: controller.answerSending,
                        submit: { controller.submitAnswer(requestID: request.id, answer: $0) },
                        endSession: { controller.stop() }, controller: controller)
                .interactiveDismissDisabled()
                .dynamicTypeSize(dynamicTypeSize)
        }
        .onDisappear { controller.stop() }
        .interactiveDismissDisabled(controller.state.isActive)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, controller.state.isActive { controller.stop() }
        }
    }

    private func copy(_ rehearsal: String, _ phone: String) -> LocalizedStringKey {
        LocalizedStringKey(phoneCall ? phone : rehearsal)
    }

    private var conversationHeader: some View {
        HStack(spacing: 12) {
            EmberMark(size: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.contactName.isEmpty ? appLocalized("Voice conversation") : definition.contactName)
                    .font(.headline)
                status.font(.subheadline).foregroundStyle(Ember.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private var status: some View {
        switch controller.state {
        case .idle: Label(copy("Ready to test", "Ready to call"), systemImage: phoneCall ? "phone" : "mic")
        case .connecting: HStack { ProgressView(); Text(copy("Connecting to OpenAI…", "Preparing Ember and calling…")) }
        case .listening: Label("Agent listening", systemImage: "ear")
        case .thinking: Label("Agent thinking", systemImage: "ellipsis.bubble")
        case .speaking: Label("Agent speaking", systemImage: "waveform")
        case .waitingForUser: Label("Waiting for your answer", systemImage: "person.crop.circle.badge.questionmark")
        case .ending: Label("Agent saying goodbye…", systemImage: "hand.wave")
        case .ended:
            if controller.endedByAgent {
                Label("The agent ended the session", systemImage: "checkmark.circle")
            } else {
                Label(copy("Voice test ended", "Phone call ended"), systemImage: "checkmark.circle")
            }
        case .failed(let message):
            if hasConversation {
                Label(copy("Rehearsal interrupted", "Phone call interrupted"), systemImage: "exclamationmark.triangle").foregroundStyle(Ember.critical)
            } else {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Ember.critical)
            }
        }
    }
}

struct TranscriptBubble: View {
    let item: RealtimeTestController.Transcript
    private var isInstruction: Bool { item.speaker == .userInstruction }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold))
                .foregroundStyle(isInstruction ? .white.opacity(0.8) : Ember.secondary)
            if item.unavailable {
                Label("Transcription unavailable for this turn.", systemImage: "exclamationmark.bubble")
                    .font(.subheadline).foregroundStyle(Ember.secondary)
            } else if item.text.isEmpty {
                Text(item.isFinal ? "No speech recognized." : "Transcribing…")
                    .font(.subheadline).foregroundStyle(Ember.secondary)
            } else {
                Text(item.text).lineSpacing(4).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .foregroundStyle(isInstruction ? .white : Ember.ink)
        .background(background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Ember.ink.opacity(isInstruction ? 0 : 0.05)))
        .padding(.leading, isInstruction ? 24 : 0).padding(.trailing, isInstruction ? 0 : 16)
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        switch item.speaker {
        case .agent: .white
        case .recipient: Ember.peach.opacity(0.45)
        case .userInstruction: Ember.ink
        }
    }
    private var title: LocalizedStringKey {
        switch item.speaker {
        case .agent: "Agent"
        case .recipient: "Other person"
        case .userInstruction: "Your instruction"
        }
    }
    private var icon: String {
        switch item.speaker {
        case .agent: "waveform"
        case .recipient: "person"
        case .userInstruction: "paperplane"
        }
    }
}
