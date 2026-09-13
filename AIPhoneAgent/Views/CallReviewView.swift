import SwiftUI

struct CallReviewView: View {
    @Environment(CallController.self) private var controller
    @Environment(AppSettings.self) private var settings
    @State private var showsRealtimeTest = false
    private var definition: CallDefinition { controller.definition }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Ready for the conversation?").font(.largeTitle.bold()).tracking(-0.8)
                Text("Check the details, then choose how to try them.")
                    .foregroundStyle(Ember.secondary)
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "calendar").font(.title2).foregroundStyle(Ember.orange)
                        .padding(16).background(Ember.peach, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(definition.contactName.isEmpty ? appLocalized("Your appointment") : definition.contactName).font(.title3.bold())
                        Text(definition.objective).foregroundStyle(Ember.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    row("Availability", value: definition.availability, fallback: "Ask me before agreeing to a time")
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Agent language").font(.subheadline.weight(.semibold)).foregroundStyle(Ember.secondary)
                        Text(LocalizedStringKey(definition.agentLanguage))
                    }
                    Divider()
                    row("Preferences & permissions", value: definition.additionalInstructions, fallback: "Follow my availability and ask about anything unknown.")
                    Divider()
                    row("Booking name", value: [settings.userIdentity.givenName, settings.userIdentity.familyName].filter { !$0.isEmpty }.joined(separator: " "), fallback: "Ember will ask when a name is needed.")
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 14) {
                    Label("Phone call · You speak", systemImage: "phone").font(.headline)
                    Text("This calls a real number using your microphone. Ember’s AI voice does not join this call yet.")
                        .font(.subheadline).foregroundStyle(Ember.secondary)
                    if definition.canPlaceCall {
                        Text(PhoneNumberInput.display(definition.phoneNumber)).font(.headline).textSelection(.enabled)
                        Button(action: controller.executeCall) {
                            Label("Call this number", systemImage: "phone.arrow.up.right")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.bordered).tint(Ember.ink).accessibilityIdentifier("review-phone-call")
                        Text("A real call will be placed. Calling charges may apply.")
                            .font(.caption).foregroundStyle(Ember.secondary)
                    } else {
                        Button("Add a valid phone number", action: controller.editCall)
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                }.padding(20).background(Ember.peach.opacity(0.35), in: RoundedRectangle(cornerRadius: 24))
            }.padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            EmberFooter {
                VStack(spacing: 10) {
                    EmberPrimaryButton(title: "Rehearse with Ember", icon: "waveform") { showsRealtimeTest = true }
                        .accessibilityIdentifier("review-rehearse")
                    Text("You play the receptionist. No phone number is dialed.")
                        .font(.caption).foregroundStyle(Ember.secondary)
                }
            }
        }
        .sheet(isPresented: $showsRealtimeTest) { RealtimeTestView(definition: definition) }
        .navigationTitle("Review details")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit", action: controller.editCall).frame(minHeight: 44)
            }
        }
    }
    private func row(_ label: LocalizedStringKey, value: String, fallback: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Ember.secondary)
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(fallback) }
            else { Text(value) }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
