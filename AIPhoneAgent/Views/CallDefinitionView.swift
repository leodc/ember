import SwiftUI

struct CallDefinitionView: View {
    @Environment(CallController.self) private var controller
    @FocusState private var focused: Bool
    @State private var showsAvailabilityPicker = false
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
                    if controller.definition.hasInvalidPhoneNumber {
                        Text("Enter a complete phone number, for example 070 1234 5678 or +81 70 1234 5678.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                field("What is the appointment for?", icon: "calendar") {
                    TextField("e.g. A dental cleaning", text: $controller.definition.objective, axis: .vertical).lineLimit(1...4)
                }
                field("When are you available?", icon: "clock") {
                    Button {
                        focused = false
                        showsAvailabilityPicker = true
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            if controller.definition.availability.isEmpty {
                                Text("Choose date and time")
                            } else {
                                Text(controller.definition.availability)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "calendar").foregroundStyle(Ember.orange)
                        }
                        .foregroundStyle(controller.definition.availability.isEmpty ? Ember.secondary : Ember.ink)
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Text("Optional. I’ll ask before agreeing if this is blank.")
                            .font(.caption).foregroundStyle(Ember.secondary)
                        Spacer()
                        if !controller.definition.availability.isEmpty {
                            Button("Clear") { controller.definition.availability = "" }
                                .font(.caption.weight(.medium))
                        }
                    }
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
            if !focused {
                EmberFooter {
                    VStack(spacing: 8) {
                        if !controller.definition.canReview {
                            Text("Add a phone number, appointment purpose, and language to continue.")
                                .font(.caption).foregroundStyle(Ember.secondary)
                        }
                        EmberPrimaryButton(title: "Review appointment") {
                            controller.reviewCall()
                        }.disabled(!controller.definition.canReview)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: focused)
        .navigationTitle("Set up an appointment")
        .sheet(isPresented: $showsAvailabilityPicker) {
            AvailabilityPickerView(availability: $controller.definition.availability)
        }
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
    private func field<Content: View>(_ title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title3).frame(width: 24).padding(.top, 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(Ember.secondary)
                content().font(.body).focused($focused).accessibilityLabel(Text(title))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Ember.ink.opacity(0.09)))
    }
}

private struct AvailabilityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Binding var availability: String
    @State private var day: Date
    @State private var startTime: Date
    @State private var endTime: Date

    init(availability: Binding<String>) {
        _availability = availability
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        let components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        let base = calendar.date(from: components) ?? tomorrow
        _day = State(initialValue: base)
        _startTime = State(initialValue: calendar.date(byAdding: .hour, value: 10, to: base) ?? base)
        _endTime = State(initialValue: calendar.date(byAdding: .hour, value: 12, to: base) ?? base)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Available day", selection: $day, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }
                Section("Time window") {
                    DatePicker("From", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: $endTime, displayedComponents: .hourAndMinute)
                    if combinedEnd <= combinedStart {
                        Text("The end time must be after the start time.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Availability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this time") {
                        availability = formattedAvailability
                        dismiss()
                    }
                    .disabled(combinedEnd <= combinedStart)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var combinedStart: Date { combined(day: day, time: startTime) }
    private var combinedEnd: Date { combined(day: day, time: endTime) }

    private var formattedAvailability: String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let date = dateFormatter.string(from: combinedStart)
        let start = timeFormatter.string(from: combinedStart)
        let end = timeFormatter.string(from: combinedEnd)
        return "\(date), \(start)–\(end)"
    }

    private func combined(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: DateComponents(
            year: dayParts.year,
            month: dayParts.month,
            day: dayParts.day,
            hour: timeParts.hour,
            minute: timeParts.minute
        )) ?? day
    }
}
