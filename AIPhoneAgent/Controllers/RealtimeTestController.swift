import Foundation
import Observation
import AVFoundation

@MainActor
@Observable
final class RealtimeTestController {
    enum State: Equatable {
        case idle, connecting, listening, thinking, speaking, waitingForUser, ending, ended, failed(String)
        var isActive: Bool {
            switch self {
            case .connecting, .listening, .thinking, .speaking, .waitingForUser, .ending: true
            default: false
            }
        }
    }
    struct Transcript: Identifiable, Equatable {
        let id: String
        let speaker: TranscriptSpeaker
        var text: String
        var isFinal = false
        var unavailable = false
    }
    private(set) var state: State = .idle
    private(set) var pendingQuestion: AskUserRequest?
    private(set) var answerSending = false
    var instructionDraft = ""
    private(set) var instructionSending = false
    private var instructionID: UUID?
    var canSendInstruction: Bool {
        state.isActive && state != .connecting && !instructionSending && !answerSending
    }
    private(set) var endedByAgent = false
    private(set) var transcripts: [Transcript] = []
    private var attempt: UUID?
    private var service: (any RealtimeServicing)?
    private var connectionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let makeService: @MainActor () -> any RealtimeServicing
    private let configuration: () throws -> RealtimeConfiguration
    private let permission: () async -> Bool

    init(makeService: @escaping @MainActor () -> any RealtimeServicing = { OpenAIRealtimeClient() },
         configuration: @escaping () throws -> RealtimeConfiguration = { try RealtimeConfiguration.load() },
         permission: @escaping () async -> Bool = { await AVAudioApplication.requestRecordPermission() }) {
        self.makeService = makeService
        self.configuration = configuration
        self.permission = permission
    }

    func start(definition: CallDefinition, language: AppLanguage) {
        guard !state.isActive else { return }
        let id = UUID()
        attempt = id
        state = .connecting
        transcripts = []
        endedByAgent = false
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let config = try self.configuration()
                let granted = await self.permission()
                guard self.attempt == id, !Task.isCancelled else { return }
                guard granted else { throw RealtimeError.permission }
                let service = self.makeService()
                self.service = service
                service.onEvent = { [weak self] event in
                    guard let self, self.attempt == id else { return }
                    self.receive(event)
                }
                self.timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(40)) } catch { return }
                    guard let self, self.attempt == id, self.state == .connecting else { return }
                    self.fail(.timeout)
                }
                try await service.start(definition: definition, language: language, configuration: config)
            } catch {
                guard self.attempt == id, !Task.isCancelled else { return }
                self.fail(error as? RealtimeError ?? .connection)
            }
        }
    }

    func sendInstruction() {
        guard canSendInstruction, let service,
              !instructionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let id = UUID()
        instructionID = id
        instructionSending = true
        do { try service.submitInstruction(id: id, text: instructionDraft) }
        catch { fail(.connection) }
    }

    func submitAnswer(requestID: UUID, answer: String) {
        guard pendingQuestion?.id == requestID, !answerSending, !instructionSending,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        answerSending = true
        do { try service?.submitAnswer(requestID: requestID, answer: answer) }
        catch { fail(.connection) }
    }

    func stop() {
        release()
        state = .ended
    }

    private func fail(_ error: RealtimeError) {
        release()
        state = .failed(error.localizedDescription)
    }

    private func release() {
        instructionID = nil
        instructionSending = false
        instructionDraft = ""
        pendingQuestion = nil
        answerSending = false
        attempt = nil
        connectionTask?.cancel()
        connectionTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        service?.onEvent = nil
        service?.stop()
        service = nil
    }

    private func receive(_ event: RealtimeEvent) {
        switch event {
        case .ready:
            timeoutTask?.cancel()
            timeoutTask = nil
            state = .listening
        case .listening: if state != .ending && pendingQuestion == nil { state = .listening }
        case .thinking: if state != .ending && pendingQuestion == nil { state = .thinking }
        case .speaking: if state != .ending && pendingQuestion == nil { state = .speaking }
        case .askUser(let request):
            guard state != .ending, pendingQuestion == nil else { return }
            pendingQuestion = request
            answerSending = false
            state = .waitingForUser
        case .questionSuperseded:
            pendingQuestion = nil
            answerSending = false
        case .instructionSubmitted(let id, let text):
            guard instructionID == id else { return }
            instructionID = nil
            instructionSending = false
            instructionDraft = ""
            updateTranscript(id: id.uuidString, text: text, final: true, speaker: .userInstruction)
            state = .thinking
        case .answerSubmitted:
            pendingQuestion = nil
            answerSending = false
            state = .thinking
        case .ending:
            pendingQuestion = nil
            answerSending = false
            state = .ending
        case .endedByAgent:
            guard state == .ending, !instructionSending else { return }
            endedByAgent = true
            release()
            state = .ended
        case .failed(let error): fail(error)
        case .transcript(let id, let text, let final, let speaker):
            updateTranscript(id: id, text: text, final: final, speaker: speaker)
        case .transcriptUnavailable(let id):
            updateTranscript(id: id, text: "", final: true, speaker: .recipient, unavailable: true)
        }
    }

    private func updateTranscript(id: String, text: String, final: Bool,
                                  speaker: TranscriptSpeaker, unavailable: Bool = false) {
        if let index = transcripts.firstIndex(where: { $0.id == id }) {
            guard !transcripts[index].isFinal else { return }
            if final { transcripts[index].text = text }
            else { transcripts[index].text += text }
            transcripts[index].isFinal = final
            transcripts[index].unavailable = unavailable
        } else {
            transcripts.append(Transcript(id: id, speaker: speaker, text: text,
                                          isFinal: final, unavailable: unavailable))
            if transcripts.count > 100 { transcripts.removeFirst() }
        }
    }
}
