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
                        if definition.contactName.isEmpty {
                            Text("Your appointment").font(.title3.bold())
                        } else {
                            Text(definition.contactName).font(.title3.bold())
                        }
                        Text(definition.phoneNumber).font(.subheadline).foregroundStyle(Ember.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    row("APPOINTMENT FOR", value: definition.objective)
                    row("YOUR AVAILABILITY", value: definition.availability, emptyFallback: "Ask me before agreeing to a time")
                    Divider()
                    row("AGENT LANGUAGE", value: definition.agentLanguage)
                    Divider()
                    row("PREFERENCES & PERMISSIONS", value: definition.additionalInstructions)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
                EmberAssurance()
            }.padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            EmberFooter {
                VStack(spacing: 12) {
                    Text("A real Telnyx call will be placed. Carrier charges may apply.")
                        .font(.caption).foregroundStyle(Ember.secondary)
                    EmberPrimaryButton(title: "Execute call", icon: "phone") { controller.executeCall() }
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
    private func row(
        _ label: LocalizedStringKey,
        value: String,
        emptyFallback: LocalizedStringKey = "Not specified"
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Ember.secondary)
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(emptyFallback).font(.body)
            } else {
                Text(value).font(.body)
            }
        }
    }
}
