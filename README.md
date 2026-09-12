# Ember

Personal iOS prototype for an AI-driven outgoing telephone call with a
human-in-the-loop `ask_user` step.

## Current scope: Milestone 2

Implemented:

- native SwiftUI call-definition form
- validation and Japanese E.164 normalization for phone numbers
- native calendar and start/end time selection for availability
- review screen
- active-call screen
- small observable `CallController`
- TelnyxRTC 4.2.0 integration through Swift Package Manager
- real outgoing PSTN calls with microphone/earpiece or speaker audio
- live connecting, connected, ending, completed, and failed states
- call duration and remote termination details

Not implemented yet: OpenAI Realtime, the audio bridge, tool calling, CallKit,
incoming calls, or any backend.

## Configure Telnyx

1. In the Telnyx Mission Control Portal, create a Credential Connection and an
   Outbound Voice Profile, then assign the profile to the connection.
2. Open `Config.local.xcconfig` and set `TELNYX_SIP_USER`, `TELNYX_PASSWORD`,
   and `TELNYX_CALLER_NUMBER`. The caller number must be a Telnyx number
   assigned to the connection. Do not add quotation marks.
3. The local config is intentionally ignored by Git. Keep
   `Config.local.xcconfig.example` as the shareable template.

## Open and run

Open `AIPhoneAgent.xcodeproj` in Xcode, choose an iPhone or iOS Simulator, set
your development team if Xcode requests it, then Run.

Manual test:

1. Tap **Set up an appointment** on the Ember home screen.
   Three additional call types are examples marked **Coming soon** and disabled.
2. Enter a phone number, request, agent language, availability, and instructions.
3. Tap **Review appointment**, check the summary, then tap **Execute call**.
4. Allow microphone access when prompted. Use a physical iPhone and keep Ember
   in the foreground for this milestone.
5. Answer the destination phone, verify two-way audio, optionally toggle the
   speaker, and end the call from either device.
6. Confirm Ember shows the completed state and duration, then return to setup.

Phone numbers should use E.164 format, for example `+819012345678`. Telnyx may
restrict destinations until the account, number, and outbound profile are
fully configured. CallKit is deliberately deferred because the milestone only
requires a foreground outgoing-call proof.

The interface uses warm ivory surfaces, amber accents, a scalable speech-bubble
and flame mark, Dynamic Type, accessible field labels, and scrolling layouts.
Primary actions remain above the bottom safe area. The initial design uses
a consistent light appearance. The installed display name is Ember; the Xcode
scheme remains AIPhoneAgent.

See `docs/AudioBridgeFeasibility.md` for the early investigation of the
critical Telnyx/OpenAI audio bridge.
