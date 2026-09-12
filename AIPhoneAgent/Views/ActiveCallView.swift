import SwiftUI

struct ActiveCallView: View {
    @Environment(CallController.self) private var controller

    private var isFinished: Bool {
        if case .failed = controller.callState { return true }
        return controller.callState == .completed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Group {
                    if isFinished { Text("CALL FINISHED") } else { Text("LIVE CALL") }
                }
                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Ember.secondary)

                ZStack {
                    Circle().fill(statusColor.opacity(0.12)).frame(width: 174, height: 174)
                    EmberMark(size: 126).shadow(color: Ember.orange.opacity(0.18), radius: 24, y: 10)
                }

                VStack(spacing: 8) {
                    Group {
                        if controller.definition.contactName.isEmpty {
                            Text("Your call")
                        } else {
                            Text(controller.definition.contactName)
                        }
                    }
                    .font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(controller.definition.phoneNumber).foregroundStyle(Ember.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(durationText(controller.elapsedTime(at: context.date)))
                            .font(.system(.title3, design: .monospaced).weight(.medium))
                            .contentTransition(.numericText())
                    }
                }

                Label { statusText } icon: { Image(systemName: statusIcon) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(statusColor)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(statusColor.opacity(0.10), in: Capsule())

                if let reason = controller.terminationReason, !reason.isEmpty {
                    Text(reason).font(.subheadline).foregroundStyle(Ember.secondary)
                        .multilineTextAlignment(.center)
                }

                if !isFinished {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Milestone 2 test", systemImage: "iphone.radiowaves.left.and.right").font(.headline)
                        Text("This call uses your iPhone microphone and its current audio output. Keep Ember open during the test.")
                            .font(.subheadline).foregroundStyle(Ember.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                }
            }
            .padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            EmberFooter {
                if isFinished {
                    EmberPrimaryButton(title: "Back to setup", icon: "arrow.left") { controller.closeCall() }
                } else {
                    HStack(spacing: 14) {
                        Button(action: controller.toggleSpeaker) {
                            Image(systemName: controller.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.wave.2")
                                .font(.title3).frame(width: 58, height: 58)
                                .foregroundStyle(controller.isSpeakerEnabled ? .white : Ember.ink)
                                .background(controller.isSpeakerEnabled ? Ember.orange : .white.opacity(0.85), in: Circle())
                        }
                        .disabled(controller.callState != .connected)
                        .accessibilityLabel(controller.isSpeakerEnabled ? Text("Use earpiece") : Text("Use speaker"))

                        Button(action: controller.endCall) {
                            Label("End call", systemImage: "phone.down.fill")
                                .font(.headline).frame(maxWidth: .infinity).frame(height: 58)
                                .foregroundStyle(.white).background(Color.red, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain).disabled(controller.callState == .ending)
                    }
                }
            }
        }
        .navigationTitle("Ember").navigationBarBackButtonHidden()
    }

    private var statusColor: Color {
        if case .failed = controller.callState { return .red }
        switch controller.callState {
        case .connected: return .green
        case .completed: return Ember.secondary
        default: return Ember.orange
        }
    }

    private var statusIcon: String {
        if case .failed = controller.callState { return "exclamationmark.triangle.fill" }
        switch controller.callState {
        case .preparing: return "mic.badge.plus"
        case .calling: return "phone.arrow.up.right"
        case .connected: return "phone.fill"
        case .ending: return "phone.down"
        case .completed: return "checkmark.circle.fill"
        default: return "phone"
        }
    }

    private var statusText: Text {
        switch controller.callState {
        case .idle: Text("Ready")
        case .preparing: Text("Preparing")
        case .calling: Text("Connecting")
        case .connected: Text("Connected")
        case .listening: Text("Agent listening")
        case .speaking: Text("Agent speaking")
        case .waitingForUser: Text("Waiting for user")
        case .ending: Text("Ending")
        case .completed: Text("Ended")
        case .failed(let message): Text("Failed") + Text(": \(message)")
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
