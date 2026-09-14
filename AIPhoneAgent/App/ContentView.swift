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
        .tint(Ember.ink)
        .preferredColorScheme(.light)
    }
}

enum Ember {
    static let background = Color(red: 0.985, green: 0.967, blue: 0.941)
    static let ink = Color(red: 0.15, green: 0.14, blue: 0.16)
    static let secondary = Color(red: 0.43, green: 0.40, blue: 0.40)
    static let orange = Color(red: 0.93, green: 0.28, blue: 0.07)
    static let positive = Color(red: 0.13, green: 0.40, blue: 0.27)
    static let critical = Color(red: 0.72, green: 0.12, blue: 0.16)
    static let accentText = Color(red: 0.68, green: 0.25, blue: 0.10)
    static let peach = Color(red: 1, green: 0.90, blue: 0.80)
    static let gradient = LinearGradient(colors: [Color(red: 1, green: 0.56, blue: 0.13), orange], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct EmberMark: View {
    var size: CGFloat = 48
    var body: some View {
        Image("EmberIcon").resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

struct EmberPrimaryButton: View {
    let title: LocalizedStringKey
    var icon = "arrow.right"
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Image(systemName: icon).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 24).padding(.vertical, 18).padding(.horizontal, 18)
            .foregroundStyle(isEnabled ? .white : Ember.secondary)
            .background(isEnabled ? Ember.ink : Ember.ink.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}

struct EmberFooter<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: 520)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Ember.background)
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
    @Environment(AppSettings.self) private var appSettings
    @State private var showsSettings = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    EmberMark(size: 42)
                    Text("Ember").font(.title2.bold())
                    Spacer()
                    Button { showsSettings = true } label: {
                        Image(systemName: "person.crop.circle").font(.title2)
                            .frame(width: 48, height: 48).background(.white, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Profile and settings")
                        .accessibilityIdentifier("home-settings")
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("A little help with the conversation.")
                        .font(.largeTitle.bold()).tracking(-0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Prepare an appointment, try it with Ember, and stay in control of every decision.")
                        .foregroundStyle(Ember.secondary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "calendar.badge.clock").font(.largeTitle).foregroundStyle(Ember.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your next appointment").font(.title2.bold())
                        Text("Set the goal, your availability, and what Ember can agree to.")
                            .foregroundStyle(Ember.secondary)
                    }
                    EmberPrimaryButton(title: controller.definition.objective.isEmpty ? "Prepare an appointment" : "Continue preparing") {
                        controller.startCall()
                    }.accessibilityIdentifier("home-prepare")
                }.padding(24).background(Ember.peach.opacity(0.6), in: RoundedRectangle(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 18) {
                    Text("Two ways to try Ember").font(.headline)
                    feature("waveform", "Rehearse with AI", "Play the receptionist. Ember speaks, asks for your input, and follows your written instructions.")
                    Divider()
                    feature("phone", "Make a phone call", "Call a real number yourself, or try a call where Ember speaks for you.")
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
                Label("Your answers and instructions stay in your hands.", systemImage: "hand.raised")
                    .font(.subheadline).foregroundStyle(Ember.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: 568).frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsSettings) {
            LanguageSettingsView(initialLanguage: appSettings.language, initialIdentity: appSettings.userIdentity)
        }
    }
    private func feature(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Ember.orange)
                .frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Ember.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LanguageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings
    @State private var draftLanguage: AppLanguage
    @State private var draftIdentity: UserIdentity

    init(initialLanguage: AppLanguage, initialIdentity: UserIdentity) {
        _draftIdentity = State(initialValue: initialIdentity)
        _draftLanguage = State(initialValue: initialLanguage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your language") {
                    Picker("App and questions", selection: $draftLanguage) {
                        Text("English").tag(AppLanguage.english)
                        Text("Spanish").tag(AppLanguage.spanish)
                    }
                    .pickerStyle(.segmented)

                    Text("Ember will use this language for its screens and for questions it asks you. The phone conversation language is configured separately for each call.")
                        .font(.footnote)
                        .foregroundStyle(Ember.secondary)
                }
                Section {
                    identityField("Given name", text: $draftIdentity.givenName)
                    identityField("Family name", text: $draftIdentity.familyName)
                    identityField("Preferred name", text: $draftIdentity.preferredName)
                } header: {
                    Text("How Ember introduces you")
                } footer: {
                    Text("Use the name you want the recipient to hear. All profile details are optional.")
                }
                Section {
                    DisclosureGroup("More details") {
                    identityField("Sex", text: $draftIdentity.sex)
                    identityField("Age in years", text: $draftIdentity.age, keyboard: .numberPad)
                    identityField("Languages spoken", text: $draftIdentity.languages)
                    identityField("Occupation", text: $draftIdentity.occupation)
                    identityField("Nationality", text: $draftIdentity.nationality)
                    identityField("Address", text: $draftIdentity.address)
                    }
                } header: {
                    Text("Your identity")
                } footer: {
                    Text("Saved on this iPhone and sent to OpenAI when you start a voice test. The agent uses these details only when relevant to your objective. Blank fields remain unknown. Age is updated manually.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ember.background)
            .navigationTitle("Profile and settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appSettings.userIdentity = draftIdentity
                        appSettings.language = draftLanguage
                        dismiss()
                    }
                }
            }
        }
        .tint(Ember.ink).preferredColorScheme(.light)
        .presentationDetents([.large])
        .interactiveDismissDisabled(draftLanguage != appSettings.language || draftIdentity != appSettings.userIdentity)
    }

    private func identityField(_ label: LocalizedStringKey, text: Binding<String>,
                               keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(Ember.secondary)
            TextField(label, text: text, axis: .vertical)
                .keyboardType(keyboard)
                .lineLimit(1...4)
        }
    }
}

#Preview {
    ContentView()
        .environment(CallController())
        .environment(AppSettings())
}
