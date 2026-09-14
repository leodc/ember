# Audio bridge feasibility note

Reviewed on 2026-09-09 against TelnyxRTC `main` at commit
`4a9fe8d86e0f20d50a7f1c0ccaafa8e15344b495` (release 4.2.0 timeframe) and its
WebRTC M150 dependency.

## Physical test accepted — 2026-09-13

The user confirms audible tone, working voice return, and hangup from both phones
and on backgrounding. Both supplied screenshots show zero callback errors and
zero delayed ticks. The native Telnyx seam is now demonstrated on the iPhone for
this probe. OpenAI/PSTN conversation remains a separate pending validation.
The next implementation uses two custom-device WebRTC peers rather than
WebSocket audio. See [the second step](Milestone5RealtimeBridge.md).

## Initial implementation — 2026-09-13

The installed version is TelnyxRTC 4.2.0 at
`99dbca66ef7005178d5a70b03bfe74512f4a4f28`, with WebRTC M150. Its actual binary
headers expose `RTCAudioDevice` and the injectable factory initializer. Ember
now vendors this exact source with a narrow, per-client audio-device patch.
A real two-peer WebRTC test in the simulator exchanged generated PCM tones in
both directions, with zero audio callback errors. The Telnyx tone/voice-return
probe is implemented for physical testing. No PSTN call has been made by the
agent and OpenAI audio is not connected yet. See [Milestone 5](Milestone5AudioBridge.md).

The original investigation below remains the rationale; its statement that
on-device feasibility is unverified still applies to a physical iPhone/PSTN call.

## Finding

WebRTC's custom audio-device seam is a candidate path for the required bridge,
but on-device feasibility has **not yet been experimentally validated**. The
bridge is **not available through TelnyxRTC's current public API**.

TelnyxRTC publicly exposes `Call.localStream` and `Call.remoteStream`. This is
useful for track state and statistics, but `RTCAudioTrack` does not expose PCM
sample callbacks in the Objective-C/Swift public API.

The SDK's `Peer` owns a static `RTCPeerConnectionFactory`, constructs it with
the standard system audio device, creates the local audio source internally,
and does not offer a factory or audio-device injection point. Therefore the app
cannot replace microphone capture with OpenAI PCM or read decoded remote PCM
using supported TelnyxRTC APIs alone.

## Smallest proof-of-concept path

1. Maintain a narrowly scoped fork of TelnyxRTC.
2. Change `Peer.factory` creation so it can receive an `RTCAudioDevice`.
3. Implement a duplex custom device that:
   - forwards WebRTC-recording requests from an OpenAI PCM ring buffer;
   - copies WebRTC playout PCM into the OpenAI Realtime input queue;
   - uses fixed, explicitly converted sample formats at each boundary.
4. First validate the custom device with a Telnyx call and loopback/generated
   tone before adding OpenAI Realtime.

This keeps Telnyx signaling, ICE, DTLS, RTP, codecs, and PSTN routing intact;
it does not rewrite SIP or WebRTC.

## Rejected shortcut

Running a separate `AVAudioEngine` tap while WebRTC owns `AVAudioSession` is not
a dependable bridge. It competes with WebRTC's audio unit, may capture the
physical microphone or mixed device output instead of the decoded remote
track, and does not provide a supported way to replace the WebRTC send source.

## Decision gate before Milestone 5

Create a disposable fork branch and prove four counters on a real iPhone:

- WebRTC playout frames received
- frames queued to OpenAI
- OpenAI frames received
- WebRTC recording frames supplied

Only after those counters move continuously during a real PSTN call should the
full bridge and UI be built.

