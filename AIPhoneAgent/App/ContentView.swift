import SwiftUI

struct ContentView: View {
    @Environment(CallController.self) private var controller
    var body: some View {
        NavigationStack {
            Group {
                switch controller.route {
                case .home: EmberHomeView()
                case .definition: CallDefinitionView()
                case .review: CallReviewView()
                case .active: ActiveCallView()
                }
            }
            .foregroundStyle(Ember.ink)
            .background(Ember.background.ignoresSafeArea())
            .toolbarBackground(Ember.background, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Ember.orange)
        .preferredColorScheme(.light)
    }
}

enum Ember {
    static let background = Color(red: 0.985, green: 0.967, blue: 0.941)
    static let ink = Color(red: 0.15, green: 0.14, blue: 0.16)
    static let secondary = Color(red: 0.43, green: 0.40, blue: 0.40)
    static let orange = Color(red: 0.93, green: 0.28, blue: 0.07)
    static let peach = Color(red: 1, green: 0.90, blue: 0.80)
    static let gradient = LinearGradient(colors: [Color(red: 1, green: 0.56, blue: 0.13), orange], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// Resolution-independent brand mark inspired by the supplied reference.
struct EmberMark: View {
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            Image(systemName: "bubble.right").resizable().scaledToFit()
                .foregroundStyle(Ember.gradient)
            Image(systemName: "flame.fill").resizable().scaledToFit()
                .foregroundStyle(Ember.gradient)
                .frame(width: size * 0.33, height: size * 0.46)
                .offset(y: -size * 0.035)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct EmberPrimaryButton: View {
    let title: String
    var icon = "arrow.right"
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.headline)
                Image(systemName: icon).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 19)
            .foregroundStyle(.white)
            .background(Ember.gradient, in: RoundedRectangle(cornerRadius: 20))
            .opacity(isEnabled ? 1 : 0.45)
        }.buttonStyle(.plain)
    }
}

struct EmberFooter<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: 520)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Ember.background.opacity(0.98))
    }
}

struct EmberAssurance: View {
    var body: some View {
        Label("If a question needs your input, I’ll ask you here.", systemImage: "checkmark.shield")
            .font(.footnote).foregroundStyle(Ember.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Ember.peach.opacity(0.30), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EmberHomeView: View {
    @Environment(CallController.self) private var controller
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    EmberMark(size: 42)
                    Text("Ember").font(.title2.weight(.bold))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your calling assistant")
                        .font(.subheadline).foregroundStyle(Ember.secondary)
                    Text("I’ll help you\nmake the call.")
                        .font(.largeTitle.weight(.bold)).tracking(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tell me what you need. I’ll follow your instructions and check with you when I need an answer.")
                        .font(.body).foregroundStyle(Ember.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("What would you like to do?").font(.headline).padding(.bottom, 4)
                    Button(action: controller.startCall) {
                    HStack(spacing: 16) {
                        Image(systemName: "calendar").font(.title2).foregroundStyle(Ember.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Set up an appointment").font(.headline).foregroundStyle(Ember.ink)
                            Text("Find a time that works for you.")
                                .font(.subheadline).foregroundStyle(Ember.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").font(.body.weight(.semibold))
                            .foregroundStyle(.white).padding(12)
                            .background(Ember.gradient, in: Circle())
                    }
                    .padding(20).background(Ember.peach.opacity(0.7), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Ember.orange.opacity(0.10)))
                    }.buttonStyle(.plain)
                    upcoming("Ask a question", icon: "questionmark.bubble", detail: "Get information from a business.")
                    upcoming("Change a reservation", icon: "calendar.badge.clock", detail: "Adjust an existing booking.")
                    upcoming("Follow up", icon: "phone.arrow.up.right", detail: "Check on a request or delivery.")
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text("You’re in control").font(.headline)
                    VStack(alignment: .leading, spacing: 20) { steps }
                }.padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 32)
            .frame(maxWidth: 568).frame(maxWidth: .infinity)
        }.toolbar(.hidden, for: .navigationBar)
    }
    private func upcoming(_ title: String, icon: String, detail: String) -> some View {
        Button {} label: {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon).font(.title3)
                    .frame(width: 26, height: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Coming soon").font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Ember.ink.opacity(0.05), in: Capsule())
                        .padding(.top, 3)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Ember.secondary)
            .padding(18)
            .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Ember.ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("\(title). Coming soon.")
    }
    @ViewBuilder private var steps: some View {
        step("text.alignleft", "Your goal", "Tell me what you want to achieve.")
        step("slider.horizontal.3", "Your boundaries", "Set what I can do and what needs your approval.")
        step("bubble.left", "Your input", "If I don’t know something, I’ll ask you here.")
    }
    private func step(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.body).foregroundStyle(Ember.orange)
                .frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(Ember.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview { ContentView().environment(CallController()) }
