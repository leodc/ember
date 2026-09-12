import Foundation
import Observation
import AVFoundation

@MainActor
@Observable
final class RealtimeTestController {
    enum State: Equatable {
        case idle, connecting, listening, thinking, speaking, ending, ended, failed(String)
        var isActive: Bool {
            switch self {
            case .connecting, .listening, .thinking, .speaking, .ending: true
            default: false
            }
        }
    }
    struct Transcript: Identifiable {
        let id: String
        var text: String
    }
    private(set) var state: State = .idle
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

    func stop() {
        release()
        state = .ended
    }

    private func fail(_ error: RealtimeError) {
        release()
        state = .failed(error.localizedDescription)
    }

    private func release() {
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
        case .listening: if state != .ending { state = .listening }
        case .thinking: if state != .ending { state = .thinking }
        case .speaking: if state != .ending { state = .speaking }
        case .ending: state = .ending
        case .endedByAgent:
            guard state == .ending else { return }
            endedByAgent = true
            release()
            state = .ended
        case .failed(let error): fail(error)
        case .transcript(let id, let text, let final):
            if let index = transcripts.firstIndex(where: { $0.id == id }) {
                if final { transcripts[index].text = text }
                else { transcripts[index].text += text }
            } else {
                transcripts.append(Transcript(id: id, text: text))
                if transcripts.count > 100 { transcripts.removeFirst() }
            }
        }
    }
}
