# TelnyxRTC local source snapshot for Ember milestone 5

Upstream: https://github.com/team-telnyx/telnyx-webrtc-ios

Release **4.2.0**, commit **99dbca66ef7005178d5a70b03bfe74512f4a4f28**,
the exact version already pinned by Ember before this experiment. Copied only
`Package.swift`, `LICENSE`, and the `TelnyxRTC` target from the clean SwiftPM
checkout. The MIT license is retained. No binaries, credentials, example app,
nested Git repository, or SDK cache modifications are required.

Xcode resolves this local Swift package. Its existing Starscream 4.0.8 and
WebRTC M150 dependencies remain pinned in the app's `Package.resolved`.

## Patch surface

Only three upstream source files differ; see `ember-audio-device.patch`:

- `TxClient.swift`: optional `audioDevice` constructor parameter (nil by default),
  forwarded to all call construction paths. Skip physical audio session and
  route operations for custom-device clients.
- `WebRTC/Call.swift`: retain the device for this call and pass it to outgoing,
  answering, and recovered peers. Disable local ringtone/ringback players when
  using the custom device.
- `WebRTC/Peer.swift`: own a factory per custom-device peer, created with the
  actual M150 `RTCPeerConnectionFactory(..., audioDevice:)` initializer. Keep the
  standard shared factory for ordinary calls. Skip physical audio configuration
  and audio-device reset heuristics for custom peers. Request no microphone DSP
  via WebRTC source constraints for the custom PCM path.

SIP, ICE, RTP, DTLS, codec negotiation, and normal microphone calls retain the
upstream implementation. Incoming calls and reconnection are not part of the
Ember probe acceptance test; the app rejects incoming calls and stops the probe
if the connected call returns to a connecting state.

## Reproduce / review

The complete patch is kept alongside the source so a reviewer can compare the
change without reading the entire vendored SDK. To reconstruct, check out the
upstream commit, copy the three paths listed above, and apply:

```sh
git apply /path/to/ember/Vendor/telnyx-webrtc-ios/ember-audio-device.patch
```

Do not edit Xcode's `SourcePackages/checkouts` to enable the experiment. Future
SDK upgrades need an explicit patch review and another physical audio test.
