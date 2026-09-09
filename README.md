# Ember

Personal iOS prototype for an AI-driven outgoing telephone call with a
human-in-the-loop `ask_user` step.

## Current scope: Milestone 1

Implemented:

- native SwiftUI call-definition form
- validation for phone, objective, and language
- review screen
- active-call placeholder
- small observable `CallController`

Not implemented yet: Telnyx, OpenAI Realtime, audio, tool calling, secrets, or
any backend.

## Open and run

Open `AIPhoneAgent.xcodeproj` in Xcode, choose an iPhone or iOS Simulator, set
your development team if Xcode requests it, then Run.

Manual test:

1. Tap **Set up an appointment** on the Ember home screen.
   Three additional call types are examples marked **Coming soon** and disabled.
2. Enter a phone number, request, agent language, availability, and instructions.
3. Tap **Review appointment**, check the summary, then tap **Preview call**.
4. Confirm the preview appears. No telephone call is placed.
5. Tap **Close preview** and confirm the form retains its values.

The interface uses warm ivory surfaces, amber accents, a scalable speech-bubble
and flame mark, Dynamic Type, accessible field labels, and scrolling layouts.
Primary actions remain above the bottom safe area. The initial design uses
a consistent light appearance. The installed display name is Ember; the Xcode
scheme remains AIPhoneAgent.

See `docs/AudioBridgeFeasibility.md` for the early investigation of the
critical Telnyx/OpenAI audio bridge.
