import Foundation
import OSLog

/// One call, two peers, on-device PCM. Reuses the M4 conversation controller and
/// tools. Telnyx is dialed only after OpenAI is ready; neither device is activated
/// until the recipient answers. Every terminal path releases both services.
@MainActor
final class BridgedCallService: RealtimeServicing, TelnyxCallServiceDelegate {
    var onEvent: ((RealtimeEvent) -> Void)?
    private enum Phase { case idle, preparing, dialing, active, stopped }
    private var phase: Phase = .idle
    private var bridge: AudioBridge?
    private var realtime: (any RealtimeServicing)?
    private var telephone: (any CallingService)?
    private var definition: CallDefinition?
    private var telephoneConfiguration: TelnyxConfiguration?
    private var monitor: Task<Void, Never>?
    private var goodbyeTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "Ember", category: "AudioBridge")
    private let makeRealtime: @MainActor (AudioBridge) -> any RealtimeServicing
    private let makeTelephone: (AudioBridge) -> any CallingService
    private let loadTelephone: () throws -> TelnyxConfiguration

    init(makeRealtime: @escaping @MainActor (AudioBridge) -> any RealtimeServicing = { bridge in
        OpenAIRealtimeClient(audioDevice: bridge.realtimeDevice,
                             onAudioInterrupted: { bridge.interruptAgent() },
                             onAudioStarted: { bridge.agentStartedSpeaking() })
    }, makeTelephone: @escaping (AudioBridge) -> any CallingService = { TelnyxCallService(audioDevice: $0.telephoneDevice) },
         loadTelephone: @escaping () throws -> TelnyxConfiguration = { try TelnyxConfiguration.load() }) {
        self.makeRealtime = makeRealtime
        self.makeTelephone = makeTelephone
        self.loadTelephone = loadTelephone
    }

    func start(definition: CallDefinition, language: AppLanguage, configuration: RealtimeConfiguration) async throws {
        guard phase == .idle, definition.canPlaceCall else { throw RealtimeError.connection }
        phase = .preparing
        self.definition = definition
        do { telephoneConfiguration = try loadTelephone() }
        catch { stop(); throw RealtimeError.telephone(error.localizedDescription) }
        let bridge = AudioBridge()
        self.bridge = bridge
        let service = makeRealtime(bridge)
        realtime = service
        service.onEvent = { [weak self] event in self?.receive(event) }
        do {
            try await service.start(definition: definition, language: language, configuration: configuration)
            try Task.checkCancellation()
        } catch {
            stop()
            throw error
        }
    }

    private func receive(_ event: RealtimeEvent) {
        guard phase != .stopped else { return }
        switch event {
        case .ready:
            guard phase == .preparing, let bridge, let definition, let telephoneConfiguration else { return }
            phase = .dialing
            let service = makeTelephone(bridge)
            telephone = service
            service.delegate = self
            startMonitor()
            do {
                try service.startCall(destinationNumber: definition.dialablePhoneNumber,
                                      callerName: "Ember", configuration: telephoneConfiguration)
                logger.info("OpenAI ready; dialing Telnyx with PCM disabled until answer")
            } catch { fail(.telephone(error.localizedDescription)) }
        case .failed(let error): fail(error)
        case .endedByAgent:
            guard phase == .active, goodbyeTask == nil else { return }
            // OpenAI already waited for its final output and 750 ms media tail.
            // Also drain local signal and allow Telnyx's remote jitter buffer a tail.
            goodbyeTask = Task { [weak self] in
                let deadline = ProcessInfo.processInfo.systemUptime + 5
                while !Task.isCancelled {
                    guard let self, self.phase == .active, let bridge = self.bridge else { return }
                    if bridge.failed { self.fail(.bridgeAudio); return }
                    if bridge.agentToRecipient.isQuiet {
                        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                        guard self.phase == .active, !Task.isCancelled else { return }
                        if !bridge.agentToRecipient.isQuiet { continue }
                        self.finish(.endedByAgent)
                        return
                    }
                    if ProcessInfo.processInfo.systemUptime > deadline { self.fail(.farewellTimeout); return }
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                }
            }
        default:
            guard phase == .active else { return }
            onEvent?(event)
        }
    }

    private func startMonitor() {
        let started = ProcessInfo.processInfo.systemUptime
        monitor = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.phase != .stopped, let bridge = self.bridge else { return }
                self.onEvent?(.bridgeDiagnostics(bridge.snapshot))
                if bridge.failed { self.fail(.bridgeAudio); return }
                if self.phase == .dialing, ProcessInfo.processInfo.systemUptime - started > 60 {
                    self.fail(.telephone(appLocalized("The test call did not connect within 60 seconds."))); return
                }
                ticks += 1
                if ticks % 5 == 0 {
                    let phone = bridge.telephoneDevice.snapshot
                    let ai = bridge.realtimeDevice.snapshot
                    let input = bridge.recipientToAgent.snapshot
                    let output = bridge.agentToRecipient.snapshot
                    self.logger.info("PCM telnyxReceived=\(phone.receivedBlocks) toOpenAI=\(input.readBlocks) openAIReceived=\(ai.receivedBlocks) toTelnyx=\(output.readBlocks) inputSignal=\(phone.nonSilentReceivedBlocks) outputSignal=\(ai.nonSilentReceivedBlocks) underflows=\(input.underflows + output.underflows) overflows=\(input.overflows + output.overflows)")
                }
            }
        }
    }

    func submitAnswer(requestID: UUID, answer: String) throws {
        guard phase == .active else { throw RealtimeError.connection }
        try realtime?.submitAnswer(requestID: requestID, answer: answer)
    }
    func submitInstruction(id: UUID, text: String) throws {
        guard phase == .active else { throw RealtimeError.connection }
        goodbyeTask?.cancel(); goodbyeTask = nil
        bridge?.interruptAgent()
        try realtime?.submitInstruction(id: id, text: text)
    }
    func stop() {
        guard phase != .stopped else { return }
        phase = .stopped
        monitor?.cancel(); monitor = nil
        goodbyeTask?.cancel(); goodbyeTask = nil
        bridge?.stop()
        if let bridge { onEvent?(.bridgeDiagnostics(bridge.snapshot)) }
        realtime?.onEvent = nil
        realtime?.stop(); realtime = nil
        telephone?.delegate = nil
        telephone?.endCall(); telephone = nil
        bridge = nil
        definition = nil; telephoneConfiguration = nil
        logger.info("Both PCM peers and telephone call released")
    }
    private func fail(_ error: RealtimeError) { finish(.failed(error)) }
    private func finish(_ event: RealtimeEvent) {
        guard phase != .stopped else { return }
        let callback = onEvent
        stop()
        callback?(event)
    }
    func telnyxServiceDidStartDialing(_ service: any CallingService) {
        guard service === telephone else { return }
        if phase == .active { fail(.telephone(appLocalized("The test call lost its connection. Start a new test."))) }
    }
    func telnyxServiceDidConnect(_ service: any CallingService) {
        guard service === telephone, phase == .dialing else { return }
        phase = .active
        bridge?.activate()
        onEvent?(.ready)
        logger.info("Recipient answered; duplex PCM bridge active")
    }
    func telnyxService(_ service: any CallingService, didEndWith reason: String?) {
        guard service === telephone else { return }
        finish(.endedByRecipient)
    }
    func telnyxService(_ service: any CallingService, didFailWith error: Error) {
        guard service === telephone else { return }
        fail(.telephone(error.localizedDescription))
    }
}
