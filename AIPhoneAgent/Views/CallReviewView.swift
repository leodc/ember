import SwiftUI

struct CallReviewView: View {
    @Environment(CallController.self) private var controller
    private var definition: CallDefinition { controller.definition }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Does everything look right?").font(.largeTitle.bold()).tracking(-1)
                HStack(spacing: 16) {
                    Image(systemName: "calendar").font(.title).foregroundStyle(Ember.orange)
                        .padding(16).background(Ember.peach, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(definition.contactName.isEmpty ? "Your appointment" : definition.contactName).font(.title3.bold())
                        Text(definition.phoneNumber).font(.subheadline).foregroundStyle(Ember.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    row("APPOINTMENT FOR", definition.objective)
                    row("YOUR AVAILABILITY", definition.availability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ask me before agreeing to a time" : definition.availability)
                    Divider()
                    row("AGENT LANGUAGE", definition.agentLanguage)
                    Divider()
                    row("PREFERENCES & PERMISSIONS", definition.additionalInstructions)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
                EmberAssurance()
            }.padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            EmberFooter {
                VStack(spacing: 12) {
                    Text("Demo preview · No phone call will be placed.")
                        .font(.caption).foregroundStyle(Ember.secondary)
                    EmberPrimaryButton(title: "Preview call", icon: "phone") { controller.executeCallPlaceholder() }
                }
            }
        }
        .navigationTitle("Review appointment")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit", action: controller.editCall).frame(minHeight: 44)
            }
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Ember.secondary)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not specified" : value)
                .font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
