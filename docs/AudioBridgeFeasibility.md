# Audio bridge feasibility note

Reviewed on 2026-09-09 against TelnyxRTC `main` at commit
`4a9fe8d86e0f20d50a7f1c0ccaafa8e15344b495` (release 4.2.0 timeframe) and its
WebRTC M150 dependency.

## Finding

The required bridge is feasible with WebRTC's custom audio-device seam, but it
is **not available through TelnyxRTC's current public API**.

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

