import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AudioBridgeProbeController: TelnyxCallServiceDelegate {
    enum State: Equatable { case idle, dialing, connected, ended, failed(String) }
    private(set) var state: State = .idle
    private(set) var counters = AudioBridgeProbeSnapshot()
    private(set) var echoEnabled = false
    private var device: AudioBridgeProbeDevice?
    private var service: (any CallingService)?
    private var monitor: Task<Void, Never>?
    private let logger = Logger(subsystem: "Ember", category: "AudioBridge")
    private let makeService: (AudioBridgeProbeDevice) -> any CallingService
    private let loadConfiguration: () throws -> TelnyxConfiguration

    init(makeService: @escaping (AudioBridgeProbeDevice) -> any CallingService = { TelnyxCallService(audioDevice: $0) },
         loadConfiguration: @escaping () throws -> TelnyxConfiguration = { try TelnyxConfiguration.load() }) {
        self.makeService = makeService
        self.loadConfiguration = loadConfiguration
    }

    var active: Bool { state == .dialing || state == .connected }

    func start(definition: CallDefinition) {
        guard !active, definition.canPlaceCall else { return }
        counters = .init()
        echoEnabled = false
        state = .dialing
        do {
            let configuration = try loadConfiguration()
            let device = AudioBridgeProbeDevice()
            self.device = device
            let service = makeService(device)
            self.service = service
            service.delegate = self
            // No microphone permission request: this device never captures it.
            try service.startCall(destinationNumber: definition.dialablePhoneNumber,
                                  callerName: "Ember", configuration: configuration)
            let started = Date()
            logger.info("PCM probe dialing; physical audio disabled")
            monitor = Task { [weak self, weak service] in
                var ticks = 0
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, let service, self.service === service else { return }
                    self.counters = self.device?.snapshot ?? self.counters
                    ticks += 1
                    if ticks % 5 == 0 {
                        let counts = self.counters
                        self.logger.info("PCM received=\(counts.receivedBlocks) signalIn=\(counts.nonSilentReceivedBlocks) supplied=\(counts.suppliedBlocks) signalOut=\(counts.nonSilentSuppliedBlocks) errors=\(counts.callbackErrors) lateTicks=\(counts.lateTicks)")
                    }
                    if self.counters.callbackErrors > 0 {
                        self.finish(.failed(appLocalized("The audio callback failed. End this test and try again.")))
                        return
                    }
                    if self.state == .dialing, Date().timeIntervalSince(started) > 60 {
                        self.finish(.failed(appLocalized("The test call did not connect within 60 seconds.")))
                        return
                    }
                }
            }
        } catch { finish(.failed(error.localizedDescription)) }
    }

    func sendTone() { if state == .connected { device?.sendTone() } }
    func toggleEcho() {
        guard state == .connected else { return }
        echoEnabled.toggle()
        device?.setEcho(echoEnabled)
    }
    func stop() { if active { finish(.ended) } }

    private func finish(_ result: State) {
        monitor?.cancel()
        monitor = nil
        device?.shutdown()
        counters = device?.snapshot ?? counters
        service?.delegate = nil
        service?.endCall()
        service = nil
        device = nil
        echoEnabled = false
        state = result
        logger.info("PCM probe stopped")
    }

    func telnyxServiceDidStartDialing(_ service: any CallingService) {
        guard self.service === service, active else { return }
        // Reconnection pauses the probe instead of sending old buffered audio.
        if state == .connected {
            finish(.failed(appLocalized("The test call lost its connection. Start a new test.")))
        }
    }
    func telnyxServiceDidConnect(_ service: any CallingService) {
        guard self.service === service, active else { return }
        state = .connected
        device?.activate()
        logger.info("PCM probe connected")
    }
    func telnyxService(_ service: any CallingService, didEndWith reason: String?) {
        guard self.service === service else { return }
        finish(.ended)
    }
    func telnyxService(_ service: any CallingService, didFailWith error: Error) {
        guard self.service === service else { return }
        finish(.failed(error.localizedDescription))
    }
}
