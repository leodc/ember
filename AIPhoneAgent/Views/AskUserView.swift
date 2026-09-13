import SwiftUI

struct AskUserView: View {
    let request: AskUserRequest
    let sending: Bool
    let submit: (String) -> Void
    let endSession: () -> Void
    let controller: RealtimeTestController
    @State private var selectedAnswer: String?
    @State private var answer = ""
    @State private var writingAnswer = false
    @State private var instructing = false
    @FocusState private var answerFocused: Bool
    @FocusState private var instructionFocused: Bool

    private var busy: Bool { sending || controller.instructionSending }
    private var usesText: Bool { writingAnswer || request.suggestedAnswers.isEmpty }
    private var response: String { usesText ? answer : selectedAnswer ?? "" }

    var body: some View {
        @Bindable var controller = controller
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label(busy ? "Sending…" : "Waiting for your answer", systemImage: busy ? "paperplane" : "person.crop.circle.badge.questionmark")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Ember.secondary)
                        if instructing {
                            Text("Guide the conversation").font(.title2.bold())
                            Text("Tell the agent what to do next. It will interrupt its current response.")
                                .foregroundStyle(Ember.secondary)
                            InstructionTextEditor(text: $controller.instructionDraft, focused: $instructionFocused)
                                .disabled(!controller.canSendInstruction).id("instruction-editor")
                            Text("A new instruction replaces this question. The agent will ask again if information is still missing.")
                                .font(.footnote).foregroundStyle(Ember.secondary)
                        } else {
                            Text(request.question).font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            if let original = request.originalQuestion, !original.isEmpty, original != request.question {
                                DisclosureGroup("Original question") {
                                    Text(original).font(.subheadline).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                }.font(.subheadline).foregroundStyle(Ember.secondary)
                            }
                            if !request.suggestedAnswers.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Choose an answer").font(.subheadline.weight(.semibold))
                                    ForEach(request.suggestedAnswers, id: \.self) { suggestion in
                                        choice(suggestion, selected: !usesText && selectedAnswer == suggestion) {
                                            selectedAnswer = suggestion
                                            writingAnswer = false
                                            answerFocused = false
                                        }
                                    }
                                    Button {
                                        writingAnswer = true
                                        selectedAnswer = nil
                                        answerFocused = true
                                    } label: {
                                        Label("Write a different answer", systemImage: "square.and.pencil")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                                    }.buttonStyle(.plain).foregroundStyle(Ember.ink).disabled(busy)
                                }
                            }
                            if usesText {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Your answer").font(.subheadline.weight(.semibold))
                                    TextField("Write response…", text: $answer, axis: .vertical)
                                        .lineLimit(3...6).focused($answerFocused)
                                        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ember.ink.opacity(answerFocused ? 0.55 : 0.12)))
                                        .disabled(busy).accessibilityIdentifier("ask-answer-field")
                                }.id("answer-editor")
                            }
                        }
                    }.padding(24).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    if answerFocused || instructionFocused {
                        withAnimation {
                            proxy.scrollTo(instructionFocused ? "instruction-editor" : "answer-editor", anchor: .bottom)
                        }
                    }
                }
            }
            .background(Ember.background)
            .foregroundStyle(Ember.ink)
            .navigationTitle(instructing ? "Instruction for the agent" : "Question for you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive, action: endSession) {
                        Image(systemName: "phone.down.fill").frame(width: 44, height: 44)
                    }.foregroundStyle(.red).accessibilityLabel("End voice test").accessibilityIdentifier("ask-end-session")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { answerFocused = false; instructionFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    SessionActionButton(title: instructing ? "Interrupt and send" : "Send answer", busy: busy) {
                        answerFocused = false
                        instructionFocused = false
                        if instructing { controller.sendInstruction() }
                        else { submit(response) }
                    }
                    .disabled(busy || (instructing
                        ? !controller.canSendInstruction || controller.instructionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        : response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .accessibilityIdentifier("ask-send")
                    Button(instructing ? "Back to question" : "Give a new instruction") {
                        answerFocused = false
                        instructionFocused = false
                        instructing.toggle()
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .foregroundStyle(Ember.ink).disabled(busy)
                        .accessibilityIdentifier("ask-switch-mode")
                }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 4)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
                .background(Ember.background)
                .overlay(alignment: .top) { Divider().overlay(Ember.ink.opacity(0.08)) }
            }
        }.tint(Ember.ink).preferredColorScheme(.light)
    }

    private func choice(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Text(text).font(.body.weight(selected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Ember.ink : Ember.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(16).frame(minHeight: 56)
            .background(selected ? Ember.peach.opacity(0.65) : .white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Ember.ink.opacity(0.65) : Ember.ink.opacity(0.1), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).foregroundStyle(Ember.ink).disabled(busy)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SessionActionButton: View {
    let title: LocalizedStringKey
    var busy = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Group {
            if busy { actionLabel.environment(\.isEnabled, true) }
            else { Button(action: action) { actionLabel }.buttonStyle(.plain) }
        }
    }

    private var actionLabel: some View {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.white) }
                Text(busy ? "Sending…" : title).font(.headline).fixedSize(horizontal: false, vertical: true)
                if !busy { Image(systemName: "arrow.up").font(.body.weight(.semibold)) }
            }
            .frame(maxWidth: .infinity, minHeight: 24).padding(.vertical, 16).padding(.horizontal, 16)
            .foregroundStyle(enabled || busy ? .white : Ember.secondary)
            .background(enabled || busy ? Ember.ink : Ember.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct InstructionTextEditor: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField("For example: ask about the price", text: $text, axis: .vertical)
            .lineLimit(4...8).focused(focused).padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ember.ink.opacity(focused.wrappedValue ? 0.55 : 0.12)))
            .accessibilityLabel("Instruction for the agent")
            .accessibilityIdentifier("instruction-editor")
    }
}

/// Compact composer; its shared draft survives a newly presented ask_user sheet.
struct InstructionComposer: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var controller: RealtimeTestController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(dynamicTypeSize.isAccessibilitySize ? "Write…" : "Give an instruction…", text: $controller.instructionDraft, axis: .vertical)
                    .lineLimit(1...3).focused($focused).padding(.vertical, 10).padding(.leading, 14)
                    .disabled(!controller.canSendInstruction)
                    .accessibilityLabel("Instruction for the agent").accessibilityIdentifier("live-instruction-field")
                Button {
                    focused = false
                    controller.sendInstruction()
                } label: {
                    Group {
                        if controller.instructionSending { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.up").font(.body.bold()) }
                    }
                    .frame(width: 44, height: 44).foregroundStyle(.white)
                    .background(canSend || controller.instructionSending ? Ember.ink : Ember.secondary.opacity(0.3), in: Circle())
                }.buttonStyle(.plain).padding(5)
                    .disabled(!canSend).accessibilityLabel("Interrupt and send")
                    .accessibilityIdentifier("live-instruction-send")
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Ember.ink.opacity(0.12)))
            if focused || !controller.instructionDraft.isEmpty || controller.instructionSending {
                Text(controller.instructionSending ? "Sending instruction…" : "Interrupts the agent immediately")
                    .font(.caption).foregroundStyle(Ember.secondary).padding(.horizontal, 8)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private var canSend: Bool {
        controller.canSendInstruction && !controller.instructionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
