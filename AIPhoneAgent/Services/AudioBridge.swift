import Foundation

/// Single-producer/single-consumer PCM boundary between independent WebRTC
/// devices. Both negotiate Int16 mono at 48 kHz; no acoustic loop or resampler.
/// A bounded 100 ms queue fails explicitly on overflow rather than accumulating
/// seconds of old speech. Underflow supplies silence, never repeats old samples.
final class BridgePCMBuffer {
    struct Snapshot: Equatable {
        var writtenBlocks = 0
        var readBlocks = 0
        var underflows = 0
        var overflows = 0
        var queuedSamples = 0
    }
    private let lock = NSLock()
    private var samples: [Int16]
    private var head = 0
    private var count = 0
    private var accepting = true
    private var stopped = false
    private var stats = Snapshot()
    private var lastSignalTime: TimeInterval = 0

    init(capacity: Int = 4_800) {
        precondition(capacity >= 480)
        samples = .init(repeating: 0, count: capacity)
    }
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
    var snapshot: Snapshot { locked { var result = stats; result.queuedSamples = count; return result } }
    var isQuiet: Bool {
        locked { ProcessInfo.processInfo.systemUptime - lastSignalTime > 0.35 }
    }
    func setAccepting(_ value: Bool) {
        locked {
            accepting = value
            head = 0; count = 0
            samples.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        }
    }
    func stop() {
        locked {
            stopped = true; accepting = false; head = 0; count = 0
            samples.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        }
    }
    func write(_ input: UnsafeBufferPointer<Int16>) {
        locked {
            guard accepting, !stopped else { return }
            guard input.count <= samples.count - count else {
                stats.overflows += 1
                stopped = true; head = 0; count = 0
                return
            }
            var hasSignal = false
            for value in input {
                samples[(head + count) % samples.count] = value
                count += 1
                if abs(Int(value)) > 64 { hasSignal = true }
            }
            if hasSignal { lastSignalTime = ProcessInfo.processInfo.systemUptime }
            stats.writtenBlocks += 1
        }
    }
    func read(into output: UnsafeMutableBufferPointer<Int16>) {
        locked {
            output.initialize(repeating: 0)
            guard !stopped else { return }
            let available = min(count, output.count)
            for index in 0..<available {
                output[index] = samples[head]
                samples[head] = 0
                head = (head + 1) % samples.count
            }
            count -= available
            if available > 0 { stats.readBlocks += 1 }
            if accepting, available < output.count { stats.underflows += 1 }
        }
    }
}

struct AudioBridgeEndpoint {
    let received: BridgePCMBuffer
    let outgoing: BridgePCMBuffer
}

struct AudioBridgeSnapshot: Equatable {
    let telephone: AudioBridgeProbeSnapshot
    let realtime: AudioBridgeProbeSnapshot
    let toAgent: BridgePCMBuffer.Snapshot
    let toRecipient: BridgePCMBuffer.Snapshot
}

final class AudioBridge {
    let recipientToAgent = BridgePCMBuffer()
    let agentToRecipient = BridgePCMBuffer()
    let telephoneDevice: AudioBridgeProbeDevice
    let realtimeDevice: AudioBridgeProbeDevice

    init() {
        telephoneDevice = AudioBridgeProbeDevice(endpoint: .init(received: recipientToAgent, outgoing: agentToRecipient))
        realtimeDevice = AudioBridgeProbeDevice(endpoint: .init(received: agentToRecipient, outgoing: recipientToAgent))
        agentToRecipient.setAccepting(false)
    }
    func activate() { telephoneDevice.activate(); realtimeDevice.activate() }
    func interruptAgent() { agentToRecipient.setAccepting(false) }
    func agentStartedSpeaking() { agentToRecipient.setAccepting(true) }
    var snapshot: AudioBridgeSnapshot {
        .init(telephone: telephoneDevice.snapshot, realtime: realtimeDevice.snapshot,
              toAgent: recipientToAgent.snapshot, toRecipient: agentToRecipient.snapshot)
    }
    var failed: Bool {
        recipientToAgent.snapshot.overflows > 0 || agentToRecipient.snapshot.overflows > 0
            || telephoneDevice.snapshot.callbackErrors > 0 || realtimeDevice.snapshot.callbackErrors > 0
    }
    func stop() {
        telephoneDevice.shutdown(); realtimeDevice.shutdown()
        recipientToAgent.stop(); agentToRecipient.stop()
    }
}
