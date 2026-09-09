import SwiftUI

struct ActiveCallView: View {
    @Environment(CallController.self) private var controller
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text("CALL PREVIEW").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Ember.secondary)
                EmberMark(size: 144)
                    .shadow(color: Ember.orange.opacity(0.2), radius: 28, y: 12).padding(.vertical, 24)
                VStack(spacing: 10) {
                    Text(controller.definition.contactName.isEmpty ? "Your call" : controller.definition.contactName)
                        .font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(controller.definition.phoneNumber).foregroundStyle(Ember.secondary)
                }
                Label("Ready when you are", systemImage: "phone")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Ember.orange)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Ember.peach.opacity(0.5), in: Capsule())
                VStack(alignment: .leading, spacing: 10) {
                    Text("The plan").font(.headline)
                    Text(controller.definition.objective).font(.body)
                    Text("This is a preview. Ember hasn’t called this number.")
                        .font(.subheadline).foregroundStyle(Ember.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 24))
            }.padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            EmberFooter {
                EmberPrimaryButton(title: "Close preview", icon: "xmark") { controller.endPlaceholderCall() }
            }
        }
        .navigationTitle("Ember").navigationBarBackButtonHidden()
    }
}
