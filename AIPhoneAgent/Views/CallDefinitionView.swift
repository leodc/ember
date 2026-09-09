import SwiftUI

struct CallDefinitionView: View {
    @Environment(CallController.self) private var controller
    @FocusState private var focused: Bool
    var body: some View {
        @Bindable var controller = controller
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let’s find a time\nthat works for you.").font(.largeTitle.weight(.bold)).tracking(-1)
                    Text("Tell me who to call and when you’re free. I’ll follow your preferences and ask if I need anything else.")
                        .font(.subheadline).foregroundStyle(Ember.secondary)
                }.padding(.bottom, 12)
                field("Who should I call?", icon: "person") {
                    TextField("Name or business", text: $controller.definition.contactName).textContentType(.name)
                }
                field("Phone number", icon: "phone") {
                    TextField("+81 …", text: $controller.definition.phoneNumber)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                }
                field("What is the appointment for?", icon: "calendar") {
                    TextField("e.g. A dental cleaning", text: $controller.definition.objective, axis: .vertical).lineLimit(1...4)
                }
                field("When are you available?", icon: "clock") {
                    TextField("e.g. Wednesday, 10 am–12 pm", text: $controller.definition.availability, axis: .vertical).lineLimit(1...3)
                    Text("Optional. If you leave this blank, I’ll ask before agreeing to a time.")
                        .font(.caption).foregroundStyle(Ember.secondary)
                }
                field("Agent language", icon: "bubble.left") {
                    TextField("e.g. Japanese", text: $controller.definition.agentLanguage)
                }
                field("Preferences & permissions", icon: "slider.horizontal.3") {
                    TextField("e.g. Choose a time within my availability. Ask me about any extra costs.", text: $controller.definition.additionalInstructions, axis: .vertical).lineLimit(2...6)
                }
                EmberAssurance().padding(.top, 4)
            }.padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            EmberFooter {
                VStack(spacing: 8) {
                    if !controller.definition.canReview {
                        Text("Add a phone number, appointment purpose, and language to continue.")
                            .font(.caption).foregroundStyle(Ember.secondary)
                    }
                    EmberPrimaryButton(title: "Review appointment") {
                        focused = false
                        controller.reviewCall()
                    }.disabled(!controller.definition.canReview)
                }
            }
        }
        .navigationTitle("Set up an appointment")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: controller.goHome) { Image(systemName: "chevron.left").frame(width: 32, height: 44) }
                    .accessibilityLabel("Back to home")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }
    private func field<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title3).frame(width: 24).padding(.top, 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(Ember.secondary)
                content().font(.body).focused($focused).accessibilityLabel(title)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ember.ink.opacity(0.09)))
    }
}
