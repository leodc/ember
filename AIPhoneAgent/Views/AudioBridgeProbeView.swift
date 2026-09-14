import SwiftUI

struct AudioBridgeProbeView: View {
    let definition: CallDefinition
    @State private var controller = AudioBridgeProbeController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(definition: CallDefinition, controller: AudioBridgeProbeController? = nil) {
        self.definition = definition
        _controller = State(initialValue: controller ?? AudioBridgeProbeController())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Audio bridge · Step 1").font(.title.bold())
                    Text("Call your test partner. Send a short tone, then enable voice return so they can hear their own voice with a delay.")
                    Text("This test uses no iPhone microphone or speaker. OpenAI is not connected yet.")
                        .foregroundStyle(Ember.secondary)
                    Text(PhoneNumberInput.display(definition.phoneNumber)).font(.headline)
                    status
                    if controller.state == .connected {
                        Button("Send a 1-second tone", action: controller.sendTone)
                            .buttonStyle(.borderedProminent).tint(Ember.orange)
                        Button(action: controller.toggleEcho) {
                            Text(controller.echoEnabled ? LocalizedStringKey("Stop voice return") : LocalizedStringKey("Enable voice return"))
                        }.buttonStyle(.bordered)
                        Text("Use the receiver on the other phone to avoid acoustic feedback. Keep this app in the foreground.")
                            .font(.subheadline).foregroundStyle(Ember.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Audio diagnostics").font(.headline)
                        counter("Received blocks", controller.counters.receivedBlocks)
                        counter("Received blocks with signal", controller.counters.nonSilentReceivedBlocks)
                        counter("Supplied blocks", controller.counters.suppliedBlocks)
                        counter("Supplied blocks with signal", controller.counters.nonSilentSuppliedBlocks)
                        counter("Remote peak (0–32768)", controller.counters.remotePeak)
                        counter("Audio callback errors", controller.counters.callbackErrors)
                        counter("Delayed audio ticks", controller.counters.lateTicks)
                        Text("Each block is 10 ms. Moving counters alone do not prove that your partner can hear the audio.")
                            .font(.caption).foregroundStyle(Ember.secondary)
                    }.padding().background(.white, in: RoundedRectangle(cornerRadius: 20))
                }.padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
            }
            .background(Ember.background)
            .safeAreaInset(edge: .bottom) {
                EmberFooter {
                    if controller.active {
                        Button("End test call", role: .destructive, action: controller.stop)
                            .buttonStyle(.borderedProminent).frame(minHeight: 48)
                    } else {
                        VStack(spacing: 8) {
                            EmberPrimaryButton(title: "Call and test audio", icon: "waveform") { controller.start(definition: definition) }
                                .disabled(!definition.canPlaceCall)
                            Text("A real call will be placed. Calling charges may apply.")
                                .font(.caption).foregroundStyle(Ember.secondary)
                        }
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { controller.stop(); dismiss() }.frame(minHeight: 44)
            } }
        }
        .interactiveDismissDisabled(controller.active)
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { controller.stop() } }
    }

    @ViewBuilder private var status: some View {
        switch controller.state {
        case .idle: Text("Ready for the audio test").font(.headline)
        case .dialing: ProgressView("Calling your test partner…")
        case .connected: Label("Connected", systemImage: "phone.fill").font(.headline)
        case .ended: Text("Test call ended").font(.headline)
        case .failed(let message): Text(message).foregroundStyle(.red)
        }
    }
    private func counter(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value, format: .number).monospacedDigit()
        }.font(.subheadline)
    }
}
