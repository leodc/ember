import Foundation
import AudioToolbox
import WebRTC

struct AudioBridgeProbeSnapshot: Equatable {
    var receivedBlocks = 0
    var suppliedBlocks = 0
    var nonSilentReceivedBlocks = 0
    var nonSilentSuppliedBlocks = 0
    var callbackErrors = 0
    var lateTicks = 0
    var remotePeak = 0
}

/// Fixed-format first milestone-5 experiment: signed Int16, mono, 48 kHz,
/// 480 samples per 10 ms. No AVAudioSession, microphone, speaker or audio file.
/// RTCAudioDevice requires a stable THREAD, not merely a serial dispatch queue.
final class AudioBridgeProbeDevice: NSObject, RTCAudioDevice {
    let deviceInputSampleRate: Double = 48_000
    let deviceOutputSampleRate: Double = 48_000
    let inputIOBufferDuration: TimeInterval = 0.01
    let outputIOBufferDuration: TimeInterval = 0.01
    let inputNumberOfChannels = 1
    let outputNumberOfChannels = 1
    let inputLatency: TimeInterval = 0
    let outputLatency: TimeInterval = 0

    private let condition = NSCondition()
    private var delegate: (any RTCAudioDeviceDelegate)?
    private var worker: Thread?
    private var running = false
    private var exited = true
    private var enabled = false
    private var inCallback = false
    private var playing = false
    private var recording = false
    private var playoutInitialized = false
    private var recordingInitialized = false
    private var permanentlyStopped = false
    private var stats = AudioBridgeProbeSnapshot()
    private var signal = AudioBridgeProbeSignal()
    private let endpoint: AudioBridgeEndpoint?

    init(endpoint: AudioBridgeEndpoint? = nil) {
        self.endpoint = endpoint
        super.init()
    }

    private func locked<T>(_ body: () -> T) -> T {
        condition.lock()
        defer { condition.unlock() }
        return body()
    }

    var isInitialized: Bool { locked { delegate != nil } }
    var isPlayoutInitialized: Bool { locked { playoutInitialized } }
    var isRecordingInitialized: Bool { locked { recordingInitialized } }
    var isPlaying: Bool { locked { playing } }
    var isRecording: Bool { locked { recording } }
    var snapshot: AudioBridgeProbeSnapshot { locked { stats } }

    func initialize(with delegate: any RTCAudioDeviceDelegate) -> Bool {
        locked {
            guard self.delegate == nil, !permanentlyStopped else { return false }
            self.delegate = delegate
            running = true
            exited = false
            let thread = Thread { [weak self] in self?.pump() }
            thread.name = "Ember PCM probe"
            thread.qualityOfService = .userInteractive
            worker = thread
            thread.start()
            return true
        }
    }

    func terminateDevice() -> Bool {
        condition.lock()
        running = false
        enabled = false
        condition.broadcast()
        while !exited { condition.wait() }
        delegate = nil
        worker = nil
        playing = false
        recording = false
        playoutInitialized = false
        recordingInitialized = false
        signal.reset()
        condition.unlock()
        return true
    }

    func initializePlayout() -> Bool { locked { playoutInitialized = true; return true } }
    func initializeRecording() -> Bool { locked { recordingInitialized = true; return true } }
    func startPlayout() -> Bool { locked { playing = true; return true } }
    func startRecording() -> Bool { locked { recording = true; return true } }
    func stopPlayout() -> Bool { locked { playing = false; return true } }
    func stopRecording() -> Bool { locked { recording = false; return true } }

    /// Only feed audio after Telnyx reports ACTIVE, never during early media.
    func activate() { locked { if !permanentlyStopped { enabled = true } } }
    func sendTone() { locked { if enabled { signal.startTone() } } }
    func setEcho(_ enabled: Bool) { locked { signal.setEcho(enabled) } }

    /// Quiesce before hangup; do not call WebRTC's terminate lifecycle ourselves.
    func shutdown() {
        condition.lock()
        permanentlyStopped = true
        enabled = false
        running = false
        condition.broadcast()
        while inCallback || !exited { condition.wait() }
        signal.reset()
        condition.unlock()
    }

    private func pump() {
        let count = AudioBridgeProbeSignal.blockSize
        let incoming = UnsafeMutablePointer<Int16>.allocate(capacity: count)
        let outgoing = UnsafeMutablePointer<Int16>.allocate(capacity: count)
        incoming.initialize(repeating: 0, count: count)
        outgoing.initialize(repeating: 0, count: count)
        defer {
            incoming.deallocate()
            outgoing.deallocate()
            locked { exited = true; condition.broadcast() }
        }
        var sampleTime: Double = 0
        var nextTick = ProcessInfo.processInfo.systemUptime
        while true {
            condition.lock()
            while running {
                let delay = nextTick - ProcessInfo.processInfo.systemUptime
                if delay <= 0 { break }
                _ = condition.wait(until: Date().addingTimeInterval(delay))
            }
            guard running else { condition.unlock(); return }
            let now = ProcessInfo.processInfo.systemUptime
            if enabled, now - nextTick > 0.02 { stats.lateTicks += 1 }
            // Never burst stale packets after scheduling stalls.
            nextTick = max(nextTick + 0.01, now + 0.005)
            guard enabled, let delegate else { condition.unlock(); continue }
            let read = playing
            let write = recording
            inCallback = true
            condition.unlock()

            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid
            sampleTime += Double(count)
            incoming.update(repeating: 0, count: count)
            var input = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(count * 2), mData: incoming))
            let readStatus = read ? delegate.getPlayoutData(&flags, &timestamp, 0, UInt32(count), &input) : noErr
            if readStatus != noErr { incoming.update(repeating: 0, count: count) }

            condition.lock()
            let peak = UnsafeBufferPointer(start: incoming, count: count).reduce(0) { max($0, abs(Int($1))) }
            if read, readStatus == noErr {
                stats.receivedBlocks += 1
                stats.remotePeak = peak
                if peak > 64 { stats.nonSilentReceivedBlocks += 1 }
            }
            if let endpoint {
                if read, readStatus == noErr {
                    endpoint.received.write(UnsafeBufferPointer(start: incoming, count: count))
                }
                if write { endpoint.outgoing.read(into: UnsafeMutableBufferPointer(start: outgoing, count: count)) }
                else { outgoing.update(repeating: 0, count: count) }
            } else {
                signal.render(remote: UnsafeBufferPointer(start: incoming, count: count),
                              into: UnsafeMutableBufferPointer(start: outgoing, count: count))
            }
            let outputPeak = UnsafeBufferPointer(start: outgoing, count: count).reduce(0) { max($0, abs(Int($1))) }
            condition.unlock()

            var output = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(count * 2), mData: outgoing))
            flags = []
            let writeStatus = write ? delegate.deliverRecordedData(&flags, &timestamp, 0, UInt32(count), &output, nil, nil) : noErr
            locked {
                if write, writeStatus == noErr {
                    stats.suppliedBlocks += 1
                    if outputPeak > 64 { stats.nonSilentSuppliedBlocks += 1 }
                }
                if readStatus != noErr || writeStatus != noErr { stats.callbackErrors += 1 }
                inCallback = false
                condition.broadcast()
            }
        }
    }
}

/// Bounded, deterministic signal generator. Accessed only under the device lock.
struct AudioBridgeProbeSignal {
    static let blockSize = 480
    private var echo = false
    private var delay = [Int16](repeating: 0, count: 14_400) // 300 ms, bounded.
    private var cursor = 0
    private var toneSamplesRemaining = 0
    private var toneSample = 0

    mutating func startTone() { toneSamplesRemaining = 48_000; toneSample = 0 }
    mutating func setEcho(_ value: Bool) { reset(); echo = value }
    mutating func reset() {
        echo = false
        delay = [Int16](repeating: 0, count: 14_400)
        cursor = 0
        toneSamplesRemaining = 0
        toneSample = 0
    }

    mutating func render(remote: UnsafeBufferPointer<Int16>, into output: UnsafeMutableBufferPointer<Int16>) {
        precondition(remote.count == Self.blockSize && output.count == Self.blockSize)
        for index in 0..<Self.blockSize {
            let delayed = delay[cursor]
            delay[cursor] = echo ? remote[index] / 2 : 0
            cursor = (cursor + 1) % delay.count
            if toneSamplesRemaining > 0 {
                // -24 dBFS with 5 ms fade-in/out; no clipping or continuous tone.
                let envelope = min(1, Double(min(toneSample, toneSamplesRemaining)) / 240)
                output[index] = Int16(2_000 * envelope * sin(2 * .pi * 440 * Double(toneSample) / 48_000))
                toneSample += 1
                toneSamplesRemaining -= 1
            } else {
                output[index] = echo ? delayed : 0
            }
        }
    }
}
