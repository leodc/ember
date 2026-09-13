#if DEBUG
import SwiftUI

/// Opt-in, local-only scenarios for visual QA. Uses the real views with a fake transport.
@MainActor
struct VisualReviewGallery: View {
    @State private var controller: RealtimeTestController
    private let service: VisualReviewService
    private let scenario: String
    private let english: Bool
    private let largeText: Bool
    private let definition: CallDefinition

    init() {
        let args = ProcessInfo.processInfo.arguments
        func argument(_ name: String, fallback: String) -> String {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return fallback }
            return args[index + 1]
        }
        scenario = argument("--visual-review", fallback: "ask-one")
        english = argument("--review-language", fallback: "es") == "en"
        largeText = args.contains("--review-accessibility")
        let service = VisualReviewService(holdAnswer: scenario == "ask-sending")
        self.service = service
        _controller = State(initialValue: RealtimeTestController(makeService: { service },
            configuration: { .init(apiKey: "visual-review-no-network", model: "visual-review") }, permission: { true }))
        definition = CallDefinition(contactName: english ? "Sakura Dental Clinic" : "Clínica dental Sakura",
            objective: english ? "Book a dental cleaning" : "Reservar una limpieza dental",
            agentLanguage: "Japanese", availability: english ? "Wednesday · 10:00–12:00" : "Miércoles · 10:00–12:00")
    }

    var body: some View {
        Group {
            if scenario.hasPrefix("app-") {
                WholeAppReviewGallery(scenario: scenario, english: english)
            } else {
                voiceScenario
            }
        }.environment(\.locale, Locale(identifier: english ? "en" : "es"))
            .dynamicTypeSize(largeText ? .accessibility3 : .large)
    }

    private var voiceScenario: some View {
        RealtimeTestView(definition: definition, controller: controller)
            .environment(\.locale, Locale(identifier: english ? "en" : "es"))
            .dynamicTypeSize(largeText ? .accessibility3 : .large)
            .task {
                if scenario == "voice-ready" { return }
                controller.start(definition: definition, language: english ? .english : .spanish)
                for _ in 0..<100 where controller.state == .connecting { await Task.yield() }
                guard !Task.isCancelled else { return }
                if scenario.hasPrefix("ask-") {
                    let question: String
                    let suggestions: [String]
                    switch scenario {
                    case "ask-one":
                        question = english ? "Can you arrive 15 minutes before your appointment?" : "¿Puedes llegar 15 minutos antes de tu cita?"
                        suggestions = [english ? "Yes, I can arrive at 10:15" : "Sí, puedo llegar a las 10:15"]
                    case "ask-ten":
                        question = english ? "Which of these available appointments works for you?" : "¿Cuál de estos horarios disponibles te viene bien?"
                        suggestions = (1...10).map { index in
                            english ? "September \(14 + index) at \(9 + index % 4):30" : "\(14 + index) de septiembre a las \(9 + index % 4):30"
                        }
                    case "ask-long":
                        question = english
                            ? "The clinic can see you on Friday at 11:30, but asks you to arrive 20 minutes early to complete a form. The cleaning lasts approximately 45 minutes. Can you attend with these conditions?"
                            : "La clínica puede atenderte el viernes a las 11:30, pero pide que llegues 20 minutos antes para completar un formulario. La limpieza dura aproximadamente 45 minutos. ¿Puedes asistir con estas condiciones?"
                        suggestions = english
                            ? ["Yes, I can arrive at 11:10 and stay until the cleaning is finished.", "I can attend at 11:30, but cannot arrive earlier. Please ask about another option."]
                            : ["Sí, puedo llegar a las 11:10 y quedarme hasta que termine la limpieza.", "Puedo asistir a las 11:30, pero no llegar antes. Consulta otra opción."]
                    case "ask-text":
                        question = english ? "Which tooth is bothering you, and when did the pain start?" : "¿Qué diente te molesta y desde cuándo empezó el dolor?"
                        suggestions = []
                    default:
                        question = english ? "Are you currently taking any medication?" : "¿Actualmente tomas algún medicamento?"
                        suggestions = english ? ["No", "Yes"] : ["No", "Sí"]
                    }
                    service.onEvent?(.askUser(AskUserRequest(callID: "visual-ask", question: question,
                        originalQuestion: "ご予約について、ご都合を確認させていただけますか？", suggestedAnswers: suggestions)))
                    if scenario == "ask-sending", let request = controller.pendingQuestion {
                        controller.submitAnswer(requestID: request.id, answer: suggestions.first ?? "Answer")
                    }
                    if scenario == "ask-streaming" {
                        // Exercise modal hit testing while the real observable transcript updates.
                        for index in 0..<3000 {
                            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                            service.onEvent?(.transcript(id: "stream-\(index / 100)", text: "Texto ", final: false))
                        }
                    }
                } else {
                    let repetitions = scenario == "voice-long" ? 6 : 1
                    for index in 0..<repetitions {
                        service.onEvent?(.transcript(id: "r\(index)", text: "水曜日は予約がいっぱいですが、金曜日の11時30分でしたらご案内できます。ご都合はいかがですか？", final: true, speaker: .recipient))
                        service.onEvent?(.transcript(id: "a\(index)", text: "ありがとうございます。本人に確認いたしますので、少々お待ちください。", final: true))
                    }
                    controller.instructionDraft = english ? "Friday also works. Ask about the price before confirming." : "También puedo el viernes. Pregunta el precio antes de confirmar."
                    controller.sendInstruction()
                    service.onEvent?(.transcript(id: "latest", text: "金曜日の11時30分で大丈夫です。予約を確定する前に、クリーニングの料金を教えていただけますか？", final: true))
                    service.onEvent?(.listening)
                    if scenario == "voice-ended" { controller.stop() }
                    if scenario == "voice-error" { service.onEvent?(.failed(.connection)) }
                    if scenario == "voice-states" {
                        service.onEvent?(.transcript(id: "pending", text: "", final: false, speaker: .recipient))
                        service.onEvent?(.transcriptUnavailable(id: "failed"))
                    }
                }
            }
    }
}

@MainActor
private final class VisualReviewService: RealtimeServicing {
    var onEvent: ((RealtimeEvent) -> Void)?
    let holdAnswer: Bool
    init(holdAnswer: Bool) { self.holdAnswer = holdAnswer }
    func start(definition: CallDefinition, language: AppLanguage, configuration: RealtimeConfiguration) async throws { onEvent?(.ready) }
    func stop() {}
    func submitAnswer(requestID: UUID, answer: String) throws {
        guard !holdAnswer else { return }
        onEvent?(.answerSubmitted)
        onEvent?(.transcript(id: "fixture-answer", text: answer, final: true))
    }
    func submitInstruction(id: UUID, text: String) throws {
        onEvent?(.questionSuperseded)
        onEvent?(.instructionSubmitted(id: id, text: text))
    }
}

/// Isolated settings and phone transport keep the gallery away from real data and calls.
@MainActor
private struct WholeAppReviewGallery: View {
    @State private var calls: CallController
    @State private var settings: AppSettings
    @State private var availability = ""
    private let scenario: String

    init(scenario: String, english: Bool) {
        self.scenario = scenario
        let phone = VisualPhoneService()
        let calls = CallController(makeService: { phone },
            loadConfiguration: { .init(sipUser: "fixture", password: "fixture", callerNumber: "+819012345678") },
            requestPermission: { $0(true) })
        if scenario != "app-home" && scenario != "app-form-empty" {
            calls.definition = CallDefinition(contactName: english ? "Sakura Dental Clinic" : "Clínica dental Sakura",
                objective: english ? "Book a dental cleaning" : "Reservar una limpieza dental",
                agentLanguage: "Japanese", availability: english ? "Wednesday, 10:00–12:00" : "Miércoles, 10:00–12:00")
        }
        if scenario == "app-form" || scenario == "app-form-empty" { calls.startCall() }
        if scenario == "app-review" { calls.reviewCall() }
        if scenario.hasPrefix("app-call") {
            calls.definition.phoneNumber = "+819012345678"
            calls.executeCall()
            phone.outcome = scenario
        }
        _calls = State(initialValue: calls)
        _settings = State(initialValue: AppSettings(language: english ? .english : .spanish,
            identity: UserIdentity(givenName: "Alex", familyName: "Rivera", preferredName: "Alex"),
            defaults: UserDefaults(suiteName: "Ember.VisualReview")!))
    }
    var body: some View {
        Group {
            if scenario == "app-settings" {
                LanguageSettingsView(initialLanguage: settings.language, initialIdentity: settings.userIdentity)
            } else if scenario == "app-availability" {
                AvailabilityPickerView(availability: $availability)
            } else {
                ContentView()
            }
        }.environment(calls).environment(settings)
    }
}

@MainActor
private final class VisualPhoneService: @preconcurrency CallingService {
    weak var delegate: (any TelnyxCallServiceDelegate)?
    var outcome = "app-call"
    func startCall(destinationNumber: String, callerName: String, configuration: TelnyxConfiguration) throws {
        delegate?.telnyxServiceDidStartDialing(self)
        if outcome == "app-call-error" { delegate?.telnyxService(self, didFailWith: TelnyxCallServiceError.connectionLost) }
        else {
            delegate?.telnyxServiceDidConnect(self)
            if outcome == "app-call-ended" { delegate?.telnyxService(self, didEndWith: nil) }
        }
    }
    func endCall() { delegate?.telnyxService(self, didEndWith: nil) }
    func setSpeaker(enabled: Bool) {}
}
#endif
