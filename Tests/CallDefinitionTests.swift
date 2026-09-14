import XCTest
@testable import AIPhoneAgent

final class CallDefinitionTests: XCTestCase {
    func testSpanishAppLanguageProvidesSpanishAgentInstruction() {
        XCTAssertEqual(AppLanguage.spanish.agentInstructionName, "Spanish")
    }

    func testInitialLanguageFollowsSpanishDeviceLanguage() {
        XCTAssertEqual(AppLanguage.defaultLanguage(for: "es-MX"), .spanish)
    }

    func testInitialLanguageUsesEnglishForOtherDeviceLanguages() {
        XCTAssertEqual(AppLanguage.defaultLanguage(for: "en-US"), .english)
        XCTAssertEqual(AppLanguage.defaultLanguage(for: "ja-JP"), .english)
        XCTAssertEqual(AppLanguage.defaultLanguage(for: nil), .english)
    }

    func testRequiredFieldsPermitReview() {
        let definition = CallDefinition(
            phoneNumber: "+811234567890",
            objective: "Book a dental cleaning",
            agentLanguage: "Japanese"
        )

        XCTAssertTrue(definition.canReview)
    }

    func testMissingPhonePermitsRehearsalButCannotDial() {
        let definition = CallDefinition(
            phoneNumber: "   ",
            objective: "Book a dental cleaning",
            agentLanguage: "Japanese"
        )

        XCTAssertTrue(definition.canReview)
        XCTAssertFalse(definition.canPlaceCall)
    }

    func testRehearsalStillRequiresObjectiveAndLanguage() {
        XCTAssertFalse(CallDefinition(objective: "  ").canReview)
        XCTAssertFalse(CallDefinition(objective: "Book", agentLanguage: "  ").canReview)
        XCTAssertFalse(CallDefinition(phoneNumber: "invalid", objective: "Book").canPlaceCall)
        XCTAssertTrue(CallDefinition(phoneNumber: "+819012345678", objective: "Book").canPlaceCall)
    }

    func testDialablePhoneNumberRemovesCommonFormatting() {
        let definition = CallDefinition(phoneNumber: "+81 (90) 1234-5678")

        XCTAssertEqual(definition.dialablePhoneNumber, "+819012345678")
    }

    func testJapaneseDomesticNumberBecomesE164() {
        let definition = CallDefinition(phoneNumber: "070 9232 2323")

        XCTAssertEqual(definition.dialablePhoneNumber, "+817092322323")
    }

    func testSpacedInternationalPrefixBecomesE164() {
        XCTAssertEqual(PhoneNumberInput.e164("+ 81 70 9232 2323"), "+817092322323")
    }

    func testOptionalJapaneseTrunkPrefixIsRemoved() {
        XCTAssertEqual(PhoneNumberInput.e164("+81 (0)70-9232-2323"), "+817092322323")
    }

    func testTelephoneURLCopiedFromContactsIsAccepted() {
        XCTAssertEqual(PhoneNumberInput.e164("tel:+81 70 9232 2323"), "+817092322323")
    }
}

@MainActor
final class CallControllerTests: XCTestCase {
    private var permissions: [@Sendable (Bool) -> Void] = []
    private var services: [FakeCallingService] = []

    private func makeController() -> CallController {
        let controller = CallController(
            makeService: {
                let service = FakeCallingService()
                self.services.append(service)
                return service
            },
            loadConfiguration: { TelnyxConfiguration(sipUser: "test", password: "test", callerNumber: "+819012345678") },
            requestPermission: { self.permissions.append($0) }
        )
        controller.definition = CallDefinition(phoneNumber: "09012345678", objective: "Test")
        return controller
    }

    func testRehearsalWithoutPhoneNeverRequestsPermissionOrDials() {
        let controller = makeController()
        controller.definition.phoneNumber = ""
        controller.reviewCall()
        XCTAssertEqual(controller.route, .review)
        controller.executeCall()
        XCTAssertEqual(controller.callState, .idle)
        XCTAssertTrue(permissions.isEmpty)
        XCTAssertTrue(services.isEmpty)
    }

    func testCancelledPermissionCannotStartCallEvenAfterRetry() async {
        let controller = makeController()
        controller.executeCall()
        controller.endCall()
        XCTAssertEqual(controller.callState, .completed)
        controller.closeCall()
        controller.executeCall()
        permissions[0](true)
        await Task.yield()
        XCTAssertTrue(services.isEmpty)
        permissions[1](true)
        await Task.yield()
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services.first?.destinations, ["+819012345678"])
    }

    func testDuplicateExecuteAndDeniedPermissionDoNotDial() async {
        let controller = makeController()
        controller.executeCall()
        controller.executeCall()
        XCTAssertEqual(permissions.count, 1)
        permissions[0](false)
        await Task.yield()
        guard case .failed = controller.callState else { return XCTFail("Expected permission failure") }
        XCTAssertTrue(services.isEmpty)
    }

    func testOldServiceEventsCannotChangeNewCall() async {
        let controller = makeController()
        controller.executeCall()
        permissions[0](true)
        await Task.yield()
        let old = services[0]
        controller.telnyxServiceDidConnect(old)
        controller.endCall()
        controller.telnyxServiceDidConnect(old)
        XCTAssertEqual(controller.callState, .ending)
        controller.telnyxService(old, didEndWith: nil)
        controller.closeCall()
        controller.executeCall()
        permissions[1](true)
        await Task.yield()
        controller.telnyxServiceDidConnect(services[1])
        controller.telnyxService(old, didFailWith: TelnyxCallServiceError.connectionLost)
        XCTAssertEqual(controller.callState, .connected)
        XCTAssertEqual(old.endCount, 1)
    }
}

private final class FakeCallingService: CallingService {
    weak var delegate: (any TelnyxCallServiceDelegate)?
    var destinations: [String] = []
    var endCount = 0
    func startCall(destinationNumber: String, callerName: String, configuration: TelnyxConfiguration) throws {
        destinations.append(destinationNumber)
    }
    func endCall() { endCount += 1 }
    func setSpeaker(enabled: Bool) {}
}

extension CallDefinitionTests {
    func testDomesticDisplayDoesNotLoseLeadingZero() {
        XCTAssertEqual(PhoneNumberInput.display("07012345678"), "070 1234 5678")
        XCTAssertEqual(PhoneNumberInput.e164(PhoneNumberInput.display("07012345678")), "+817012345678")
    }

    func testInvalidCharactersAreNotSilentlyDialed() {
        for input in ["+819012345678 ext 12", "+8190+12345678", "+00123456789", "Call 09012345678"] {
            XCTAssertFalse(PhoneNumberInput.isPlausible(input), input)
        }
        XCTAssertTrue(PhoneNumberInput.isPlausible("０９０１２３４５６７８"))
    }

    func testOwnedErrorsFollowSelectedLanguage() {
        let previous = UserDefaults.standard.object(forKey: AppLanguage.storageKey)
        defer { UserDefaults.standard.set(previous, forKey: AppLanguage.storageKey) }
        UserDefaults.standard.set("es", forKey: AppLanguage.storageKey)
        XCTAssertEqual(TelnyxCallServiceError.connectionLost.localizedDescription, "Se perdió la conexión con Telnyx.")
        UserDefaults.standard.set("en", forKey: AppLanguage.storageKey)
        XCTAssertEqual(TelnyxCallServiceError.connectionLost.localizedDescription, "The connection to Telnyx was lost.")
    }
}

@MainActor
final class RealtimeMilestoneTests: XCTestCase {
    func testContextPreservesCallDetailsAndIndependentLanguages() throws {
        let definition = CallDefinition(contactName: "Dental Test", phoneNumber: "+819012345678",
                                        objective: "Cleaning", agentLanguage: "Japanese",
                                        availability: "Wednesday 10:00–12:00", additionalInstructions: "No extra treatments")
        let context = RealtimeSessionContext.instructions(for: definition, userLanguage: .spanish)
        for value in ["Dental Test", "Cleaning", "Japanese", "Wednesday 10:00–12:00", "No extra treatments", "Spanish"] {
            XCTAssertTrue(context.contains(value))
        }
        XCTAssertFalse(context.contains(definition.phoneNumber))
        XCTAssertFalse(context.contains("ask_user is not available yet"))
        let session = RealtimeSessionContext.session(for: definition, userLanguage: .english, model: "test-model")
        XCTAssertEqual(session["model"] as? String, "test-model")
        XCTAssertEqual((session["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }, ["ask_user", "end_session"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: session))
    }

    func testCancellationWhilePermissionPendingDoesNotCreateSession() async {
        var permissionResult: CheckedContinuation<Bool, Never>?
        var created = 0
        let controller = RealtimeTestController(makeService: { created += 1; return FakeRealtimeService() },
            configuration: { .init(apiKey: "test", model: "test") },
            permission: { await withCheckedContinuation { permissionResult = $0 } })
        controller.start(definition: .init(), language: .spanish)
        for _ in 0..<100 where permissionResult == nil { await Task.yield() }
        XCTAssertNotNil(permissionResult)
        controller.stop()
        permissionResult?.resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(created, 0)
        XCTAssertEqual(controller.state, .ended)
    }

    func testDuplicateStartAndLateEventsAreIgnored() async {
        let first = FakeRealtimeService()
        let second = FakeRealtimeService()
        var created = 0
        let controller = RealtimeTestController(makeService: {
            created += 1
            return created == 1 ? first : second
        }, configuration: { .init(apiKey: "test", model: "test") }, permission: { true })
        controller.start(definition: .init(), language: .spanish)
        controller.start(definition: .init(), language: .spanish)
        for _ in 0..<100 where first.onEvent == nil { await Task.yield() }
        XCTAssertEqual(created, 1)
        let lateEvent = first.onEvent
        first.onEvent?(.ready)
        first.onEvent?(.transcript(id: "a", text: "こん", final: false))
        first.onEvent?(.transcript(id: "a", text: "にちは", final: false))
        XCTAssertEqual(controller.transcripts.first?.text, "こんにちは")
        controller.stop()
        XCTAssertTrue(first.stopped)
        controller.start(definition: .init(), language: .english)
        for _ in 0..<100 where second.onEvent == nil { await Task.yield() }
        second.onEvent?(.ready)
        lateEvent?(.failed(.connection))
        XCTAssertEqual(controller.state, .listening)
        second.onEvent?(.failed(.connection))
        XCTAssertTrue(second.stopped)
        guard case .failed = controller.state else { return XCTFail("Expected a visible failure") }
    }

    func testPermissionDeniedAndMissingConfiguration() async {
        var created = false
        let denied = RealtimeTestController(makeService: { created = true; return FakeRealtimeService() },
            configuration: { .init(apiKey: "test", model: "test") }, permission: { false })
        denied.start(definition: .init(), language: .english)
        for _ in 0..<100 where denied.state == .connecting { await Task.yield() }
        XCTAssertFalse(created)
        guard case .failed = denied.state else { return XCTFail("Expected permission failure") }
        let missing = RealtimeTestController(configuration: { throw RealtimeError.configuration }, permission: {
            XCTFail("Should validate configuration before requesting permission"); return true
        })
        missing.start(definition: .init(), language: .english)
        for _ in 0..<100 where missing.state == .connecting { await Task.yield() }
        guard case .failed = missing.state else { return XCTFail("Expected configuration failure") }
    }
}

@MainActor
private final class FakeRealtimeService: RealtimeServicing {
    var onEvent: ((RealtimeEvent) -> Void)?
    var stopped = false
    var answers: [(UUID, String)] = []
    var answerError = false
    var instructions: [(UUID, String)] = []
    func submitInstruction(id: UUID, text: String) throws {
        if answerError { throw RealtimeError.connection }
        instructions.append((id, text))
    }
    func submitAnswer(requestID: UUID, answer: String) throws {
        if answerError { throw RealtimeError.connection }
        answers.append((requestID, answer))
    }
    func start(definition: CallDefinition, language: AppLanguage, configuration: RealtimeConfiguration) async throws {}
    func stop() { stopped = true }
}

final class UserIdentityTests: XCTestCase {
    func testExistingProfileGainsSexWithoutLosingEdits() throws {
        let suite = "EmberSexMigration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = UserIdentity(givenName: "Edited name", address: "")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        old.removeValue(forKey: "sex")
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: UserIdentity.storageKey)
        original.sex = "Hombre"
        XCTAssertEqual(UserIdentity.load(from: defaults), original)
        original.sex = ""
        original.save(to: defaults)
        XCTAssertEqual(UserIdentity.load(from: defaults).sex, "")
    }

    func testInitialProfileAndSavedEditsIncludingEmptyFields() throws {
        let suite = "EmberIdentityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(UserIdentity.load(from: defaults), .initial)
        var profile = UserIdentity.initial
        profile.givenName = "Test name"
        profile.address = ""
        profile.save(to: defaults)
        XCTAssertEqual(UserIdentity.load(from: defaults), profile)
        UserIdentity().save(to: defaults)
        XCTAssertEqual(UserIdentity.load(from: defaults), UserIdentity())
    }

    func testProfileContextUsesSessionSnapshotAndEscapesFieldValues() throws {
        var profile = UserIdentity(givenName: "Test", familyName: "Person", preferredName: "T")
        profile.address = "Line one\n\"quoted\""
        var definition = CallDefinition(contactName: "Recipient", objective: "Appointment", agentLanguage: "Japanese")
        definition.userIdentity = profile
        profile.givenName = "Changed later"
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(definition.userIdentity.agentContext.utf8)) as? [String: String])
        XCTAssertEqual(values["Given name"], "Test")
        XCTAssertEqual(values["Address"], "Line one\n\"quoted\"")
        XCTAssertEqual(values["Age in years (manually maintained)"], "")
        let context = RealtimeSessionContext.instructions(for: definition, userLanguage: .spanish)
        XCTAssertTrue(context.contains(definition.userIdentity.agentContext))
        XCTAssertTrue(context.contains("RECIPIENT: Recipient"))
        XCTAssertEqual(definition.agentLanguage, "Japanese")
    }
}

final class RealtimeFarewellTests: XCTestCase {
    func testGenerationMustWaitForPlaybackAndIgnoreOlderResponses() {
        var progress = RealtimeFarewellProgress()
        progress.responseID = "goodbye"
        progress.generationCompleted(id: "goodbye")
        XCTAssertFalse(progress.isComplete)
        progress.playbackStopped(id: "previous-response")
        XCTAssertFalse(progress.isComplete)
        progress.playbackStopped(id: "goodbye")
        XCTAssertTrue(progress.isComplete)
    }

    func testPlaybackBeforeGenerationDoesNotCloseEarly() {
        var progress = RealtimeFarewellProgress()
        progress.responseID = "goodbye"
        progress.playbackStopped(id: "goodbye")
        XCTAssertFalse(progress.isComplete)
        progress.generationCompleted(id: "old")
        XCTAssertFalse(progress.isComplete)
        progress.generationCompleted(id: "goodbye")
        XCTAssertTrue(progress.isComplete)
    }

    @MainActor
    func testAgentCompletionReleasesServiceAndRejectsLateEvents() async {
        let service = FakeRealtimeService()
        let controller = RealtimeTestController(makeService: { service },
            configuration: { .init(apiKey: "test", model: "test") }, permission: { true })
        controller.start(definition: .init(), language: .spanish)
        for _ in 0..<100 where service.onEvent == nil { await Task.yield() }
        let lateEvent = service.onEvent
        service.onEvent?(.ready)
        service.onEvent?(.ending)
        service.onEvent?(.speaking)
        service.onEvent?(.listening)
        XCTAssertEqual(controller.state, .ending)
        XCTAssertFalse(service.stopped)
        service.onEvent?(.endedByAgent)
        XCTAssertTrue(service.stopped)
        XCTAssertTrue(controller.endedByAgent)
        XCTAssertEqual(controller.state, .ended)
        lateEvent?(.speaking)
        XCTAssertEqual(controller.state, .ended)
    }

    @MainActor
    func testManualStopDuringGoodbyeCannotBecomeAgentCompletion() async {
        let service = FakeRealtimeService()
        let controller = RealtimeTestController(makeService: { service },
            configuration: { .init(apiKey: "test", model: "test") }, permission: { true })
        controller.start(definition: .init(), language: .spanish)
        for _ in 0..<100 where service.onEvent == nil { await Task.yield() }
        let lateEvent = service.onEvent
        service.onEvent?(.ending)
        controller.stop()
        lateEvent?(.endedByAgent)
        XCTAssertEqual(controller.state, .ended)
        XCTAssertFalse(controller.endedByAgent)
        XCTAssertTrue(service.stopped)
    }
}


final class RealtimeEndReasonTests: XCTestCase {
    @MainActor
    func testFinalSpokenResponseUsesTheValidatedClosingReason() throws {
        for reason in [RealtimeEndReason.objectiveCompleted, .pendingClosureAgreed, .recipientRequestedEnd] {
            var sent: [[String: Any]] = []
            let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
            let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["reason": reason.rawValue]), as: UTF8.self)
            let event: [String: Any] = ["type": "response.done", "response": ["id": "r", "status": "completed", "output": [["type": "function_call", "name": "end_session", "call_id": "end", "arguments": arguments]]]]
            client.receive(try JSONSerialization.data(withJSONObject: event))
            let final = try XCTUnwrap(sent.last { $0["type"] as? String == "response.create" }?["response"] as? [String: Any])
            let instruction = try XCTUnwrap(final["instructions"] as? String)
            XCTAssertTrue(instruction.contains("one or two short sentences"))
            if reason == .objectiveCompleted { XCTAssertTrue(instruction.contains("not proof of a booking")) }
            if reason == .pendingClosureAgreed { XCTAssertTrue(instruction.contains("request remains pending")) }
            if reason == .recipientRequestedEnd { XCTAssertTrue(instruction.contains("stop promptly")) }
            XCTAssertEqual(final["tool_choice"] as? String, "none")
            client.stop()
        }
    }

    func testUnknownInformationIsNotAClosingReason() {
        for arguments in ["{}", "{\"reason\":\"missing_information\"}",
                          "{\"reason\":\"cannot_proceed\"}", "invalid",
                          "{\"reason\":true}",
                          "{\"reason\":\"objective_completed\",\"extra\":\"value\"}"] {
            XCTAssertNil(RealtimeEndReason.parse(arguments: arguments))
        }
    }

    func testOnlySupportedExplicitReasonsAreAccepted() throws {
        for reason in RealtimeEndReason.allCases {
            let data = try JSONSerialization.data(withJSONObject: ["reason": reason.rawValue])
            XCTAssertEqual(RealtimeEndReason.parse(arguments: String(decoding: data, as: UTF8.self)), reason)
        }
    }
}

@MainActor
final class AskUserTests: XCTestCase {
    private func request(_ callID: String = "ask-1") -> AskUserRequest {
        AskUserRequest(callID: callID, question: "¿Tomas medicamentos?",
                       originalQuestion: "薬を飲んでいますか？", suggestedAnswers: ["No", "Sí"])
    }

    private func emit(_ client: OpenAIRealtimeClient, _ event: [String: Any]) throws {
        client.receive(try JSONSerialization.data(withJSONObject: event))
    }

    private func tool(_ name: String = "ask_user", id: String = "ask-1",
                      arguments: String = #"{"question":"¿Tomas medicamentos?","suggestedAnswers":["No","Sí"]}"#) -> [String: Any] {
        ["type": "function_call", "name": name, "call_id": id, "arguments": arguments]
    }

    private func done(_ client: OpenAIRealtimeClient, calls: [[String: Any]], id: String = "r1") throws {
        try emit(client, ["type": "response.done", "response": ["id": id, "status": "completed", "output": calls]])
    }

    func testParserRejectsMalformedArgumentsAndAllowsNoSuggestions() {
        for value in ["{}", "invalid", #"{"question":" ","suggestedAnswers":[]}"#,
                      #"{"question":"Q","suggestedAnswers":[2]}"#,
                      #"{"question":"Q","suggestedAnswers":[],"originalQuestion":2}"#,
                      #"{"question":"Q","suggestedAnswers":[],"extra":true}"#] {
            XCTAssertNil(AskUserRequest.parse(callID: "a", arguments: value))
        }
        XCTAssertNotNil(AskUserRequest.parse(callID: "a", arguments: #"{"question":"Q","suggestedAnswers":[]}"#))
    }

    func testToolWaitsAndReturnsExactAnswerOnlyOnce() throws {
        var sent: [[String: Any]] = []
        var pending: AskUserRequest?
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .askUser(let request) = $0 { pending = request } }
        try done(client, calls: [tool()])
        let question = try XCTUnwrap(pending)
        XCTAssertTrue(sent.isEmpty, "No result or continuation before user input")
        try done(client, calls: [tool()])
        XCTAssertEqual(pending?.id, question.id)
        try client.submitAnswer(requestID: UUID(), answer: "wrong request")
        try client.submitAnswer(requestID: question.id, answer: "   ")
        XCTAssertTrue(sent.isEmpty)
        let answer = "No. \"Solo vitaminas\"\n毎日"
        try client.submitAnswer(requestID: question.id, answer: answer)
        try client.submitAnswer(requestID: question.id, answer: "duplicate")
        XCTAssertEqual(sent.count, 2)
        let item = try XCTUnwrap(sent.first?["item"] as? [String: Any])
        XCTAssertEqual(item["call_id"] as? String, "ask-1")
        XCTAssertEqual(item["type"] as? String, "function_call_output")
        let output = try XCTUnwrap(item["output"] as? String)
        let payload = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]
        XCTAssertEqual(payload?["answer"], answer)
        XCTAssertEqual(sent.last?["type"] as? String, "response.create")
        client.stop()
    }

    func testAnswerDuringGenerationWaitsAndStopDiscardsIt() throws {
        var sent: [[String: Any]] = []
        var pending: AskUserRequest?
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .askUser(let request) = $0 { pending = request } }
        try done(client, calls: [tool()])
        try emit(client, ["type": "response.created", "response": ["id": "r2"]])
        try client.submitAnswer(requestID: XCTUnwrap(pending).id, answer: "No")
        XCTAssertTrue(sent.isEmpty)
        try done(client, calls: [], id: "r2")
        XCTAssertEqual(sent.count, 2)
        try done(client, calls: [tool(id: "ask-2")], id: "r3")
        try emit(client, ["type": "response.created", "response": ["id": "r4"]])
        try client.submitAnswer(requestID: XCTUnwrap(pending).id, answer: "late")
        client.stop()
        try done(client, calls: [], id: "r4")
        XCTAssertEqual(sent.count, 2)
    }

    func testPendingQuestionBlocksCompletionButAllowsRecipientEnd() throws {
        var sent: [[String: Any]] = []
        var ending = false
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .ending = $0 { ending = true } }
        try done(client, calls: [tool()])
        try done(client, calls: [tool("end_session", id: "end-1", arguments: #"{"reason":"objective_completed"}"#)], id: "r2")
        XCTAssertFalse(ending)
        XCTAssertEqual(sent.count, 1)
        try done(client, calls: [tool("end_session", id: "end-2", arguments: #"{"reason":"recipient_requested_end"}"#)], id: "r3")
        XCTAssertTrue(ending)
        let items = sent.compactMap { $0["item"] as? [String: Any] }
        XCTAssertEqual(items.filter { $0["call_id"] as? String == "ask-1" }.count, 1)
        XCTAssertTrue((items.first { $0["call_id"] as? String == "ask-1" }?["output"] as? String)?.contains("cancelled") == true)
        client.stop()
    }

    func testInvalidAndConcurrentToolsReceiveRejectionWithoutReplacingQuestion() throws {
        var sent: [[String: Any]] = []
        var questions: [AskUserRequest] = []
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .askUser(let request) = $0 { questions.append(request) } }
        try done(client, calls: [tool(id: "bad", arguments: "{}")])
        XCTAssertEqual(sent.count, 2)
        try done(client, calls: [tool(), tool(id: "extra")], id: "r2")
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first?.callID, "ask-1")
        XCTAssertEqual(sent.count, 3)
        client.stop()
    }

    func testControllerKeepsWaitingAndRejectsDuplicateAndOldModalAnswers() async throws {
        let service = FakeRealtimeService()
        let controller = RealtimeTestController(makeService: { service },
            configuration: { .init(apiKey: "test", model: "test") }, permission: { true })
        controller.start(definition: .init(), language: .spanish)
        for _ in 0..<100 where service.onEvent == nil { await Task.yield() }
        service.onEvent?(.ready)
        let question = request()
        service.onEvent?(.askUser(question))
        for event: RealtimeEvent in [.listening, .thinking, .speaking] { service.onEvent?(event) }
        XCTAssertEqual(controller.state, .waitingForUser)
        controller.submitAnswer(requestID: question.id, answer: "No")
        controller.submitAnswer(requestID: question.id, answer: "Sí")
        XCTAssertEqual(service.answers.count, 1)
        XCTAssertTrue(controller.answerSending)
        service.onEvent?(.answerSubmitted)
        XCTAssertNil(controller.pendingQuestion)
        XCTAssertEqual(controller.state, .thinking)
        let lateEvent = service.onEvent
        controller.stop()
        controller.start(definition: .init(), language: .english)
        for _ in 0..<100 where service.onEvent == nil { await Task.yield() }
        let next = request("ask-2")
        service.onEvent?(.askUser(next))
        controller.submitAnswer(requestID: question.id, answer: "old")
        lateEvent?(.askUser(question))
        XCTAssertEqual(controller.pendingQuestion?.id, next.id)
        XCTAssertEqual(service.answers.count, 1)
        service.onEvent?(.ending)
        XCTAssertNil(controller.pendingQuestion)
        controller.submitAnswer(requestID: next.id, answer: "late")
        XCTAssertEqual(service.answers.count, 1)
        controller.stop()
    }

    func testSpeechAndDuplicateCompletionCannotPrematurelySendQueuedAnswer() throws {
        var sent: [[String: Any]] = []
        var pending: AskUserRequest?
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .askUser(let request) = $0 { pending = request } }
        try done(client, calls: [tool()])
        try emit(client, ["type": "input_audio_buffer.speech_started"])
        try client.submitAnswer(requestID: XCTUnwrap(pending).id, answer: "No")
        XCTAssertTrue(sent.isEmpty)
        try emit(client, ["type": "input_audio_buffer.speech_stopped"])
        try done(client, calls: [tool()]) // Duplicate r1 must not finish the upcoming VAD response.
        XCTAssertTrue(sent.isEmpty)
        try emit(client, ["type": "response.created", "response": ["id": "r2"]])
        try done(client, calls: [], id: "r2")
        XCTAssertEqual(sent.count, 2)
        client.stop()
    }

    func testQuestionAndCompletionInSameResponseCannotCloseRegardlessOfOrder() throws {
        for endFirst in [true, false] {
            var pending: AskUserRequest?
            var ending = false
            let client = OpenAIRealtimeClient(sendEvent: { _ in })
            client.onEvent = {
                if case .askUser(let request) = $0 { pending = request }
                if case .ending = $0 { ending = true }
            }
            let end = tool("end_session", id: "end", arguments: #"{"reason":"objective_completed"}"#)
            try done(client, calls: endFirst ? [end, tool()] : [tool(), end])
            XCTAssertNotNil(pending)
            XCTAssertFalse(ending)
            client.stop()
        }
    }

    func testSendFailureClearsModalAndClosesSession() async {
        let service = FakeRealtimeService()
        service.answerError = true
        let controller = RealtimeTestController(makeService: { service },
            configuration: { .init(apiKey: "test", model: "test") }, permission: { true })
        controller.start(definition: .init(), language: .english)
        for _ in 0..<100 where service.onEvent == nil { await Task.yield() }
        let question = request()
        service.onEvent?(.askUser(question))
        controller.submitAnswer(requestID: question.id, answer: "No")
        XCTAssertNil(controller.pendingQuestion)
        XCTAssertTrue(service.stopped)
        guard case .failed = controller.state else { return XCTFail("Expected failure") }
    }
}

@MainActor
final class ConversationTranscriptTests: XCTestCase {
    private func connectedController() async -> (RealtimeTestController, FakeRealtimeService, OpenAIRealtimeClient) {
        let service = FakeRealtimeService()
        let controller = RealtimeTestController(makeService: { service },
            configuration: { .init(apiKey: "test", model: "test") }, permission: { true })
        controller.start(definition: .init(), language: .spanish)
        for _ in 0..<100 where service.onEvent == nil { await Task.yield() }
        service.onEvent?(.ready)
        let client = OpenAIRealtimeClient(sendEvent: { _ in })
        client.onEvent = { service.onEvent?($0) }
        return (controller, service, client)
    }

    private func emit(_ client: OpenAIRealtimeClient, type: String, id: String,
                      fields: [String: Any] = [:]) throws {
        var event = fields
        event["type"] = type
        event["item_id"] = id
        client.receive(try JSONSerialization.data(withJSONObject: event))
    }

    func testDelayedRecipientTextKeepsItsTurnBeforeAgentAndFinalReplacesDeltas() async throws {
        let (controller, _, client) = await connectedController()
        try emit(client, type: "input_audio_buffer.speech_started", id: "person1")
        try emit(client, type: "input_audio_buffer.committed", id: "person1")
        try emit(client, type: "response.output_audio_transcript.delta", id: "agent1", fields: ["delta": "こんにちは"])
        try emit(client, type: "input_audio_buffer.committed", id: "person2")
        // The next turn can finish transcribing before the first turn.
        try emit(client, type: "conversation.item.input_audio_transcription.completed", id: "person2", fields: ["transcript": "薬は？"])
        try emit(client, type: "conversation.item.input_audio_transcription.delta", id: "person1", fields: ["delta": "歯科"])
        try emit(client, type: "conversation.item.input_audio_transcription.delta", id: "person1", fields: ["delta": "です"])
        XCTAssertEqual(controller.transcripts.first?.text, "歯科です")
        try emit(client, type: "conversation.item.input_audio_transcription.completed", id: "person1", fields: ["transcript": "歯科医院です。"])
        try emit(client, type: "conversation.item.input_audio_transcription.delta", id: "person1", fields: ["delta": "late duplicate"])
        XCTAssertEqual(controller.transcripts.map(\.id), ["person1", "agent1", "person2"])
        XCTAssertEqual(controller.transcripts.map(\.speaker), [.recipient, .agent, .recipient])
        XCTAssertEqual(controller.transcripts.first?.text, "歯科医院です。")
        XCTAssertTrue(controller.transcripts.first?.isFinal == true)
        controller.stop()
        client.stop()
    }

    func testTranscriptionFailureDoesNotEndVoiceOrDismissPendingQuestion() async throws {
        let (controller, service, client) = await connectedController()
        let question = AskUserRequest(callID: "ask", question: "¿Tomas medicamentos?", originalQuestion: nil, suggestedAnswers: [])
        service.onEvent?(.askUser(question))
        try emit(client, type: "input_audio_buffer.committed", id: "person1")
        try emit(client, type: "conversation.item.input_audio_transcription.failed", id: "person1")
        XCTAssertEqual(controller.state, .waitingForUser)
        XCTAssertEqual(controller.pendingQuestion?.id, question.id)
        XCTAssertTrue(controller.transcripts.first?.unavailable == true)
        XCTAssertFalse(service.stopped)
        controller.stop()
        client.stop()
    }

    func testCompletedOnlyTranscriptAndOldSessionEvents() async throws {
        let (controller, service, client) = await connectedController()
        try emit(client, type: "conversation.item.input_audio_transcription.completed", id: "person1", fields: ["transcript": "No appointments today."])
        XCTAssertEqual(controller.transcripts.first?.speaker, .recipient)
        let late = service.onEvent
        controller.stop()
        late?(.transcript(id: "late", text: "stale", final: true, speaker: .recipient))
        XCTAssertEqual(controller.transcripts.count, 1)
        client.stop()
    }
}

@MainActor
final class LiveInstructionTests: XCTestCase {
    private func emit(_ client: OpenAIRealtimeClient, _ event: [String: Any]) throws {
        client.receive(try JSONSerialization.data(withJSONObject: event))
    }
    private func created(_ client: OpenAIRealtimeClient, id: String = "r1", goodbye: Bool = false) throws {
        try emit(client, ["type": "response.created", "response": ["id": id,
            "metadata": goodbye ? ["ember_final_goodbye": "true"] : [:]]])
    }
    private func done(_ client: OpenAIRealtimeClient, id: String = "r1", status: String = "completed", output: [[String: Any]] = []) throws {
        try emit(client, ["type": "response.done", "response": ["id": id, "status": status, "output": output]])
    }
    private func endCall() -> [String: Any] {
        ["type": "function_call", "name": "end_session", "call_id": "end1", "arguments": #"{"reason":"recipient_requested_end"}"#]
    }
    private func askCall(id: String = "ask1") -> [String: Any] {
        ["type": "function_call", "name": "ask_user", "call_id": id,
         "arguments": #"{"question":"¿Tomas medicamentos?","suggestedAnswers":["No"]}"#]
    }
    private func messages(_ sent: [[String: Any]]) -> [[String: Any]] {
        sent.compactMap { $0["item"] as? [String: Any] }.filter { $0["type"] as? String == "message" }
    }

    func testInstructionIsExactTrustedTextAndCannotBeSentTwice() throws {
        var sent: [[String: Any]] = []
        var submitted = 0
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .instructionSubmitted = $0 { submitted += 1 } }
        let id = UUID()
        let text = "Pregunta por \"limpieza\".\n金曜日も大丈夫"
        try client.submitInstruction(id: id, text: " ")
        XCTAssertTrue(sent.isEmpty)
        try client.submitInstruction(id: id, text: text)
        try client.submitInstruction(id: id, text: text)
        let item = try XCTUnwrap(messages(sent).first)
        XCTAssertEqual(item["role"] as? String, "system")
        let content = try XCTUnwrap((item["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(content.hasPrefix("APP_USER_INSTRUCTION\n"))
        let json = String(content.dropFirst("APP_USER_INSTRUCTION\n".count))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])?["instruction"], text)
        XCTAssertEqual(messages(sent).count, 1)
        XCTAssertEqual(submitted, 1)
        XCTAssertEqual(sent.filter { $0["type"] as? String == "response.create" }.count, 1)
        client.stop()
    }

    func testActiveResponseIsCancelledAndClearedBeforeReplacementAndStaleToolCannotEnd() throws {
        var sent: [[String: Any]] = []
        var ending = false
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .ending = $0 { ending = true } }
        try created(client)
        try emit(client, ["type": "output_audio_buffer.started", "response_id": "r1"])
        try client.submitInstruction(id: UUID(), text: "Antes pregunta el precio")
        XCTAssertEqual(sent.prefix(3).compactMap { $0["type"] as? String },
                       ["session.update", "response.cancel", "output_audio_buffer.clear"])
        XCTAssertEqual(sent[1]["response_id"] as? String, "r1")
        XCTAssertTrue(messages(sent).isEmpty)
        try done(client, output: [endCall()])
        XCTAssertFalse(ending)
        XCTAssertEqual(messages(sent).count, 1)
        let tool = sent.compactMap { $0["item"] as? [String: Any] }.first { $0["call_id"] as? String == "end1" }
        XCTAssertTrue((tool?["output"] as? String)?.contains("superseded_by_instruction") == true)
        client.stop()
    }

    func testLateCancelErrorAfterCompletionDoesNotFailNewResponse() throws {
        var sent: [[String: Any]] = []
        var failed = false
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .failed = $0 { failed = true } }
        try created(client)
        try client.submitInstruction(id: UUID(), text: "Pregunta el precio")
        let cancelID = try XCTUnwrap(sent.first { $0["type"] as? String == "response.cancel" }?["event_id"] as? String)
        try done(client, status: "cancelled")
        try created(client, id: "r2")
        try emit(client, ["type": "error", "error": ["event_id": cancelID, "code": "response_cancel_not_active"]])
        XCTAssertFalse(failed)
        XCTAssertEqual(messages(sent).count, 1)
        client.stop()
    }

    func testCancelRaceWithNoActiveResponseIgnoresLateDoneAndPreservesReplacement() throws {
        var sent: [[String: Any]] = []
        var ending = false
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = { if case .ending = $0 { ending = true } }
        try created(client)
        try client.submitInstruction(id: UUID(), text: "Espera, pregunta otra cosa")
        let cancelID = try XCTUnwrap(sent.first { $0["type"] as? String == "response.cancel" }?["event_id"] as? String)
        try emit(client, ["type": "error", "error": ["event_id": cancelID, "code": "response_cancel_not_active"]])
        try created(client, id: "r2")
        try done(client, output: [endCall()])
        XCTAssertFalse(ending)
        try client.submitInstruction(id: UUID(), text: "Y pregunta la duración")
        XCTAssertEqual(sent.last { $0["type"] as? String == "response.cancel" }?["response_id"] as? String, "r2")
        client.stop()
    }

    func testPendingQuestionIsSupersededWithoutInventingAnswerAndCanBeAskedAgain() throws {
        var sent: [[String: Any]] = []
        var questions = 0
        var superseded = false
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = {
            if case .askUser = $0 { questions += 1 }
            if case .questionSuperseded = $0 { superseded = true }
        }
        try done(client, output: [askCall()])
        try client.submitInstruction(id: UUID(), text: "Pregunta si puedo llevar ese dato después")
        XCTAssertTrue(superseded)
        let item = try XCTUnwrap(sent.compactMap { $0["item"] as? [String: Any] }.first { $0["call_id"] as? String == "ask1" })
        let payload = try JSONSerialization.jsonObject(with: Data((try XCTUnwrap(item["output"] as? String)).utf8)) as? [String: String]
        XCTAssertEqual(payload?["status"], "superseded_by_instruction")
        XCTAssertNil(payload?["answer"])
        try done(client, id: "r2", output: [askCall(id: "ask2")])
        XCTAssertEqual(questions, 2)
        client.stop()
    }

    func testInstructionInterruptsGoodbyeWithoutEndingSession() throws {
        var sent: [[String: Any]] = []
        var failed = false
        var ended = false
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        client.onEvent = {
            if case .failed = $0 { failed = true }
            if case .endedByAgent = $0 { ended = true }
        }
        try done(client, output: [endCall()])
        try created(client, id: "bye", goodbye: true)
        try client.submitInstruction(id: UUID(), text: "No termines todavía, pregunta la dirección")
        try done(client, id: "bye", status: "cancelled")
        try emit(client, ["type": "output_audio_buffer.stopped", "response_id": "bye"])
        XCTAssertFalse(failed)
        XCTAssertFalse(ended)
        XCTAssertEqual(messages(sent).count, 1)
        client.stop()
    }

    func testStopDiscardsQueuedInstructionAndLateGeneration() throws {
        var sent: [[String: Any]] = []
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        try created(client)
        try client.submitInstruction(id: UUID(), text: "No se debe enviar después de cerrar")
        client.stop()
        try done(client, status: "cancelled")
        try client.submitInstruction(id: UUID(), text: "Tardía")
        XCTAssertTrue(messages(sent).isEmpty)
    }

    func testInstructionDuringUpcomingVADResponseCancelsWhenIDArrives() throws {
        var sent: [[String: Any]] = []
        let client = OpenAIRealtimeClient(sendEvent: { sent.append($0) })
        try emit(client, ["type": "input_audio_buffer.speech_stopped"])
        try client.submitInstruction(id: UUID(), text: "También puedo el jueves")
        XCTAssertTrue(messages(sent).isEmpty)
        XCTAssertFalse(sent.contains { $0["type"] as? String == "response.cancel" })
        try created(client)
        XCTAssertTrue(sent.contains { $0["type"] as? String == "response.cancel" })
        try done(client, status: "cancelled")
        XCTAssertEqual(messages(sent).count, 1)
        client.stop()
    }

    func testUserRequestedEndRequiresAnInstructionInThisSession() throws {
        for hasInstruction in [false, true] {
            var ending = false
            let client = OpenAIRealtimeClient(sendEvent: { _ in })
            client.onEvent = { if case .ending = $0 { ending = true } }
            if hasInstruction { try client.submitInstruction(id: UUID(), text: "Termina la llamada") }
            let end: [String: Any] = ["type": "function_call", "name": "end_session", "call_id": "end-user",
                                      "arguments": #"{"reason":"user_requested_end"}"#]
            try done(client, output: [end])
            XCTAssertEqual(ending, hasInstruction)
            client.stop()
        }
    }

    func testControllerRetainsDraftWhileSendingAndRejectsDuplicatesAndLateAcknowledgments() async throws {
        let service = FakeRealtimeService()
        let controller = RealtimeTestController(makeService: { service },
            configuration: { .init(apiKey: "test", model: "test") }, permission: { true })
        controller.start(definition: .init(), language: .spanish)
        for _ in 0..<100 where service.onEvent == nil { await Task.yield() }
        XCTAssertFalse(controller.canSendInstruction)
        service.onEvent?(.ready)
        controller.instructionDraft = "También puedo el viernes"
        controller.sendInstruction()
        controller.sendInstruction()
        XCTAssertEqual(service.instructions.count, 1)
        XCTAssertTrue(controller.instructionSending)
        XCTAssertFalse(controller.instructionDraft.isEmpty)
        let instruction = try XCTUnwrap(service.instructions.first)
        service.onEvent?(.instructionSubmitted(id: instruction.0, text: instruction.1))
        XCTAssertEqual(controller.transcripts.last?.speaker, .userInstruction)
        XCTAssertEqual(controller.transcripts.last?.text, instruction.1)
        XCTAssertTrue(controller.instructionDraft.isEmpty)
        service.onEvent?(.ending)
        XCTAssertTrue(controller.canSendInstruction)
        controller.instructionDraft = "Espera"
        controller.sendInstruction()
        service.onEvent?(.endedByAgent)
        XCTAssertTrue(controller.state.isActive)
        let late = service.onEvent
        controller.stop()
        late?(.instructionSubmitted(id: instruction.0, text: "late"))
        XCTAssertEqual(controller.state, .ended)
        XCTAssertEqual(controller.transcripts.count, 1)
    }
}

final class AudioBridgeProbeSignalTests: XCTestCase {
    private func render(_ signal: inout AudioBridgeProbeSignal, value: Int16 = 0) -> [Int16] {
        let input = [Int16](repeating: value, count: 480)
        var output = [Int16](repeating: -1, count: 480)
        input.withUnsafeBufferPointer { incoming in
            output.withUnsafeMutableBufferPointer { signal.render(remote: incoming, into: $0) }
        }
        return output
    }
    func testDefaultIsSilenceEvenWithRemoteSpeech() {
        var signal = AudioBridgeProbeSignal()
        for _ in 0..<40 { XCTAssertTrue(render(&signal, value: 20_000).allSatisfy { $0 == 0 }) }
    }
    func testToneIsBoundedAndStopsAfterOneSecond() {
        var signal = AudioBridgeProbeSignal()
        signal.startTone()
        let samples = (0..<100).flatMap { _ in render(&signal) }
        XCTAssertEqual(samples.count, 48_000)
        XCTAssertGreaterThan(samples.map { abs(Int($0)) }.max()!, 1_900)
        XCTAssertLessThanOrEqual(samples.map { abs(Int($0)) }.max()!, 2_000)
        XCTAssertEqual(samples.first, 0)
        XCTAssertTrue(render(&signal).allSatisfy { $0 == 0 })
    }
    func testEchoDelays300msAndAttenuatesWithoutOverflow() {
        var signal = AudioBridgeProbeSignal()
        signal.setEcho(true)
        for _ in 0..<30 { XCTAssertTrue(render(&signal, value: .min).allSatisfy { $0 == 0 }) }
        XCTAssertTrue(render(&signal).allSatisfy { $0 == -16_384 })
    }
    func testDisablingEchoClearsPreviouslyReceivedAudio() {
        var signal = AudioBridgeProbeSignal()
        signal.setEcho(true)
        for _ in 0..<40 { _ = render(&signal, value: 10_000) }
        signal.setEcho(false)
        XCTAssertTrue(render(&signal).allSatisfy { $0 == 0 })
        signal.setEcho(true)
        XCTAssertTrue(render(&signal).allSatisfy { $0 == 0 })
    }
    func testResetCancelsToneAndEcho() {
        var signal = AudioBridgeProbeSignal()
        signal.setEcho(true)
        signal.startTone()
        _ = render(&signal, value: 10_000)
        signal.reset()
        for _ in 0..<40 { XCTAssertTrue(render(&signal).allSatisfy { $0 == 0 }) }
    }
}

@MainActor
final class AudioBridgeProbeControllerTests: XCTestCase {
    private let definition = CallDefinition(phoneNumber: "09012345678", objective: "Audio test")
    func testInvalidNumberCannotCreateService() {
        var creations = 0
        let controller = AudioBridgeProbeController(makeService: { _ in creations += 1; return FakeCallingService() })
        controller.start(definition: .init(phoneNumber: "invalid", objective: "Test"))
        XCTAssertEqual(creations, 0)
        XCTAssertEqual(controller.state, .idle)
    }
    func testDuplicateStartAndStopAndLateConnect() {
        let service = FakeCallingService()
        let controller = AudioBridgeProbeController(makeService: { _ in service }, loadConfiguration: {
            .init(sipUser: "test", password: "test", callerNumber: "+819012345678")
        })
        controller.start(definition: definition)
        controller.start(definition: definition)
        XCTAssertEqual(service.destinations.count, 1)
        controller.stop()
        controller.stop()
        controller.telnyxServiceDidConnect(service)
        XCTAssertEqual(controller.state, .ended)
        XCTAssertEqual(service.endCount, 1)
        XCTAssertNil(service.delegate)
    }
    func testRemoteHangupStopsEchoAndRejectsStaleEventsAfterRestart() {
        let first = FakeCallingService(), second = FakeCallingService()
        var creations = 0
        let controller = AudioBridgeProbeController(makeService: { _ in
            creations += 1; return creations == 1 ? first : second
        }, loadConfiguration: { .init(sipUser: "test", password: "test", callerNumber: "+819012345678") })
        controller.start(definition: definition)
        controller.telnyxServiceDidConnect(first)
        controller.toggleEcho()
        XCTAssertTrue(controller.echoEnabled)
        controller.telnyxService(first, didEndWith: nil)
        XCTAssertFalse(controller.echoEnabled)
        controller.start(definition: definition)
        controller.telnyxService(first, didEndWith: nil)
        XCTAssertEqual(controller.state, .dialing)
        controller.stop()
    }
    func testConfigurationFailureDoesNotDial() {
        var creations = 0
        let controller = AudioBridgeProbeController(makeService: { _ in creations += 1; return FakeCallingService() },
            loadConfiguration: { throw RealtimeError.configuration })
        controller.start(definition: definition)
        XCTAssertEqual(creations, 0)
        guard case .failed = controller.state else { return XCTFail("Expected configuration failure") }
    }
}

import WebRTC

/// Uses the real M150 binary with two local peers, no Telnyx/OpenAI account.
/// This proves the native PCM seam, not PSTN audio on a physical iPhone.
@MainActor
final class AudioBridgeNativeTests: XCTestCase {
    func testTwoCustomDevicesExchangeToneWithoutHardwareAudio() async throws {
        weak var releasedFirst: AudioBridgeProbeDevice?
        weak var releasedSecond: AudioBridgeProbeDevice?
        try await exchangeTone { first, second in
            releasedFirst = first
            releasedSecond = second
        }
        for _ in 0..<100 where releasedFirst != nil || releasedSecond != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(releasedFirst, "A's pump and native delegate must release after closing")
        XCTAssertNil(releasedSecond, "B's pump and native delegate must release after closing")
    }

    private func exchangeTone(onDevices: (AudioBridgeProbeDevice, AudioBridgeProbeDevice) -> Void) async throws {
        let first = AudioBridgeProbeDevice(), second = AudioBridgeProbeDevice()
        onDevices(first, second)
        let factoryA = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil, audioDevice: first)
        let factoryB = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil, audioDevice: second)
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let a = try XCTUnwrap(factoryA.peerConnection(with: config, constraints: constraints, delegate: nil))
        let b = try XCTUnwrap(factoryB.peerConnection(with: config, constraints: constraints, delegate: nil))
        defer {
            first.shutdown(); second.shutdown()
            a.close(); b.close()
        }
        a.add(factoryA.audioTrack(withTrackId: "tone-a"), streamIds: ["a"])
        b.add(factoryB.audioTrack(withTrackId: "tone-b"), streamIds: ["b"])
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            a.offer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: RealtimeError.connection) }
            }
        }
        try await set(offer, on: a, local: true)
        try await gathered(a)
        try await set(try XCTUnwrap(a.localDescription), on: b, local: false)
        let answer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            b.answer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: RealtimeError.connection) }
            }
        }
        try await set(answer, on: b, local: true)
        try await gathered(b)
        try await set(try XCTUnwrap(b.localDescription), on: a, local: false)
        first.activate(); second.activate()
        // Let ICE/DTLS complete and prove both callback directions run.
        for _ in 0..<100 {
            if first.snapshot.suppliedBlocks > 20 && second.snapshot.suppliedBlocks > 20 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        first.sendTone(); second.sendTone()
        for _ in 0..<100 {
            if first.snapshot.nonSilentReceivedBlocks > 10 && second.snapshot.nonSilentReceivedBlocks > 10 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(first.snapshot.nonSilentReceivedBlocks, 10, "A must receive B's generated tone")
        XCTAssertGreaterThan(second.snapshot.nonSilentReceivedBlocks, 10, "B must receive A's generated tone")
        XCTAssertGreaterThan(first.snapshot.nonSilentSuppliedBlocks, 10)
        XCTAssertGreaterThan(second.snapshot.nonSilentSuppliedBlocks, 10)
        XCTAssertEqual(first.snapshot.callbackErrors + second.snapshot.callbackErrors, 0)
        first.shutdown(); second.shutdown()
        let stoppedA = first.snapshot, stoppedB = second.snapshot
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stoppedA, first.snapshot)
        XCTAssertEqual(stoppedB, second.snapshot)
    }

    private func set(_ sdp: RTCSessionDescription, on peer: RTCPeerConnection, local: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion: (Error?) -> Void = { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            if local { peer.setLocalDescription(sdp, completionHandler: completion) }
            else { peer.setRemoteDescription(sdp, completionHandler: completion) }
        }
    }
    private func gathered(_ peer: RTCPeerConnection) async throws {
        for _ in 0..<100 {
            if peer.iceGatheringState == .complete { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RealtimeError.timeout
    }
}

final class BridgePCMBufferTests: XCTestCase {
    private func write(_ samples: [Int16], to buffer: BridgePCMBuffer) { samples.withUnsafeBufferPointer { buffer.write($0) } }
    private func read(_ buffer: BridgePCMBuffer, count: Int = 480) -> [Int16] {
        var result = [Int16](repeating: -1, count: count)
        result.withUnsafeMutableBufferPointer { buffer.read(into: $0) }
        return result
    }
    func testFIFOOrderAndSilenceOnUnderflow() {
        let buffer = BridgePCMBuffer(capacity: 480)
        write([1, 2, 3], to: buffer)
        XCTAssertEqual(Array(read(buffer).prefix(5)), [1, 2, 3, 0, 0])
        XCTAssertTrue(read(buffer).allSatisfy { $0 == 0 })
        XCTAssertEqual(buffer.snapshot.underflows, 2)
    }
    func testRingWrapPreservesOrder() {
        let buffer = BridgePCMBuffer(capacity: 480)
        write((0..<400).map(Int16.init), to: buffer)
        XCTAssertEqual(read(buffer, count: 300), (0..<300).map(Int16.init))
        write((400..<700).map(Int16.init), to: buffer)
        XCTAssertEqual(read(buffer, count: 400), (300..<700).map(Int16.init))
    }
    func testOverflowFailsClosedAndCannotReplayOldSpeech() {
        let buffer = BridgePCMBuffer(capacity: 480)
        write(.init(repeating: 2000, count: 480), to: buffer)
        write([1], to: buffer)
        XCTAssertEqual(buffer.snapshot.overflows, 1)
        XCTAssertTrue(read(buffer).allSatisfy { $0 == 0 })
        buffer.setAccepting(true)
        write([3000], to: buffer)
        XCTAssertTrue(read(buffer).allSatisfy { $0 == 0 })
    }
    func testInterruptionDiscardsBufferedAndSubsequentOldAudio() {
        let buffer = BridgePCMBuffer()
        write([3000], to: buffer)
        buffer.setAccepting(false)
        write([4000], to: buffer)
        XCTAssertTrue(read(buffer).allSatisfy { $0 == 0 })
        buffer.setAccepting(true)
        write([5000], to: buffer)
        XCTAssertEqual(read(buffer).first, 5000)
    }
    func testStopIsPermanent() {
        let buffer = BridgePCMBuffer()
        buffer.stop(); buffer.setAccepting(true)
        write([1000], to: buffer)
        XCTAssertEqual(buffer.snapshot.writtenBlocks, 0)
        XCTAssertTrue(read(buffer).allSatisfy { $0 == 0 })
    }
}

@MainActor
final class BridgedCallServiceTests: XCTestCase {
    private let definition = CallDefinition(phoneNumber: "09012345678", objective: "Book a cleaning")
    private let config = RealtimeConfiguration(apiKey: "test", model: "test")
    private func make(_ ai: FakeRealtimeService, _ phone: FakeCallingService) -> BridgedCallService {
        .init(makeRealtime: { _ in ai }, makeTelephone: { _ in phone },
              loadTelephone: { .init(sipUser: "test", password: "test", callerNumber: "+819012345678") })
    }
    func testDialOnlyAfterOpenAIReadyAndReadyOnlyAfterAnswer() async throws {
        let ai = FakeRealtimeService(), phone = FakeCallingService()
        let service = make(ai, phone)
        defer { service.stop() }
        var readyCount = 0
        service.onEvent = { if case .ready = $0 { readyCount += 1 } }
        try await service.start(definition: definition, language: .spanish, configuration: config)
        XCTAssertTrue(phone.destinations.isEmpty)
        ai.onEvent?(.ready); ai.onEvent?(.ready)
        XCTAssertEqual(phone.destinations.count, 1)
        XCTAssertEqual(readyCount, 0)
        service.telnyxServiceDidConnect(phone)
        service.telnyxServiceDidConnect(phone)
        XCTAssertEqual(readyCount, 1)
    }
    func testStopBeforeReadyCannotDialFromLateCallback() async throws {
        let ai = FakeRealtimeService(), phone = FakeCallingService()
        let service = make(ai, phone)
        try await service.start(definition: definition, language: .spanish, configuration: config)
        let late = ai.onEvent
        service.stop(); service.stop()
        late?(.ready)
        XCTAssertTrue(phone.destinations.isEmpty)
        XCTAssertTrue(ai.stopped)
    }
    func testRecipientHangupReleasesBothAndIgnoresStaleEvents() async throws {
        let ai = FakeRealtimeService(), phone = FakeCallingService()
        let service = make(ai, phone)
        var endings = 0
        service.onEvent = { if case .endedByRecipient = $0 { endings += 1 } }
        try await service.start(definition: definition, language: .spanish, configuration: config)
        ai.onEvent?(.ready)
        service.telnyxServiceDidConnect(phone)
        service.telnyxService(phone, didEndWith: nil)
        service.telnyxService(phone, didEndWith: nil)
        XCTAssertEqual(endings, 1)
        XCTAssertEqual(phone.endCount, 1)
        XCTAssertTrue(ai.stopped)
        XCTAssertNil(phone.delegate)
    }
    func testOpenAIFailureHangsUpPhone() async throws {
        let ai = FakeRealtimeService(), phone = FakeCallingService()
        let service = make(ai, phone)
        var failures = 0
        service.onEvent = { if case .failed = $0 { failures += 1 } }
        try await service.start(definition: definition, language: .spanish, configuration: config)
        ai.onEvent?(.ready)
        ai.onEvent?(.failed(.connection))
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(phone.endCount, 1)
        XCTAssertTrue(ai.stopped)
    }
    func testAnswersAndInstructionsReachSameRealtimeSession() async throws {
        let ai = FakeRealtimeService(), phone = FakeCallingService()
        let service = make(ai, phone)
        defer { service.stop() }
        try await service.start(definition: definition, language: .spanish, configuration: config)
        XCTAssertThrowsError(try service.submitInstruction(id: UUID(), text: "Before answer"))
        ai.onEvent?(.ready); service.telnyxServiceDidConnect(phone)
        let id = UUID()
        try service.submitAnswer(requestID: id, answer: "No")
        try service.submitInstruction(id: id, text: "Ask about parking")
        XCTAssertEqual(ai.answers.first?.0, id)
        XCTAssertEqual(ai.answers.first?.1, "No")
        XCTAssertEqual(ai.instructions.first?.1, "Ask about parking")
    }
    func testInstructionCancelsPendingAgentHangup() async throws {
        let ai = FakeRealtimeService(), phone = FakeCallingService()
        let service = make(ai, phone)
        defer { service.stop() }
        try await service.start(definition: definition, language: .spanish, configuration: config)
        ai.onEvent?(.ready); service.telnyxServiceDidConnect(phone)
        ai.onEvent?(.endedByAgent)
        try service.submitInstruction(id: UUID(), text: "Wait, one more question")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(phone.endCount, 0)
        XCTAssertFalse(ai.stopped)
    }
    func testAgentEndWaitsForTelnyxTailThenReleasesBoth() async throws {
        let ai = FakeRealtimeService(), phone = FakeCallingService()
        let service = make(ai, phone)
        defer { service.stop() }
        let ended = expectation(description: "Agent end forwarded after audio tail")
        service.onEvent = { if case .endedByAgent = $0 { ended.fulfill() } }
        try await service.start(definition: definition, language: .spanish, configuration: config)
        ai.onEvent?(.ready); service.telnyxServiceDidConnect(phone)
        ai.onEvent?(.endedByAgent)
        XCTAssertEqual(phone.endCount, 0)
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(phone.endCount, 1)
        XCTAssertTrue(ai.stopped)
    }
    func testPhoneContextDoesNotClaimRehearsalAndRetainsTools() {
        let session = RealtimeSessionContext.session(for: definition, userLanguage: .spanish, model: "test", telephone: true)
        let instructions = session["instructions"] as? String ?? ""
        XCTAssertTrue(instructions.contains("real outgoing telephone call"))
        XCTAssertFalse(instructions.contains("local voice rehearsal"))
        XCTAssertTrue(instructions.contains("Book a cleaning"))
        XCTAssertEqual((session["tools"] as? [[String: Any]])?.count, 2)
        XCTAssertTrue(RealtimeSessionContext.instructions(for: definition, userLanguage: .spanish).contains("local voice rehearsal"))
    }
}

extension AudioBridgeNativeTests {
    func testFourPeersRelayBothDirectionsAndGateInterruptedOutput() async throws {
        let bridge = AudioBridge()
        let phoneRemote = AudioBridgeProbeDevice(), aiRemote = AudioBridgeProbeDevice()
        let devices = [phoneRemote, bridge.telephoneDevice, bridge.realtimeDevice, aiRemote]
        let factories = devices.map { RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil, audioDevice: $0) }
        let config = RTCConfiguration(); config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let peers = try factories.map { try XCTUnwrap($0.peerConnection(with: config, constraints: constraints, delegate: nil)) }
        defer {
            devices.forEach { $0.shutdown() }
            bridge.stop()
            peers.forEach { $0.close() }
            withExtendedLifetime(factories) {}
        }
        for index in 0..<4 {
            peers[index].add(factories[index].audioTrack(withTrackId: "relay-\(index)"), streamIds: ["relay-\(index)"])
        }
        try await connectPair(peers[0], peers[1], constraints: constraints)
        try await connectPair(peers[2], peers[3], constraints: constraints)
        devices.forEach { $0.activate() }
        for _ in 0..<100 {
            if devices.allSatisfy({ $0.snapshot.suppliedBlocks > 20 }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        phoneRemote.sendTone()
        for _ in 0..<100 {
            if aiRemote.snapshot.nonSilentReceivedBlocks > 10 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(aiRemote.snapshot.nonSilentReceivedBlocks, 10, "Recipient PCM must cross both connections")
        XCTAssertEqual(phoneRemote.snapshot.nonSilentReceivedBlocks, 0, "The bridge must not echo reception's voice back")
        bridge.agentStartedSpeaking()
        aiRemote.sendTone()
        for _ in 0..<100 {
            if phoneRemote.snapshot.nonSilentReceivedBlocks > 10 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(phoneRemote.snapshot.nonSilentReceivedBlocks, 10, "Agent PCM must cross back to reception")
        bridge.interruptAgent()
        try await Task.sleep(for: .milliseconds(400)) // Drain the remote peer's RTP jitter tail.
        let before = phoneRemote.snapshot.nonSilentReceivedBlocks
        aiRemote.sendTone()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(phoneRemote.snapshot.nonSilentReceivedBlocks, before, "Interrupted output stays gated until a new response starts")
        XCTAssertFalse(bridge.failed)
        XCTAssertEqual(bridge.snapshot.toAgent.overflows + bridge.snapshot.toRecipient.overflows, 0)
    }

    private func connectPair(_ a: RTCPeerConnection, _ b: RTCPeerConnection, constraints: RTCMediaConstraints) async throws {
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            a.offer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: RealtimeError.connection) }
            }
        }
        try await set(offer, on: a, local: true); try await gathered(a)
        try await set(try XCTUnwrap(a.localDescription), on: b, local: false)
        let answer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            b.answer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: RealtimeError.connection) }
            }
        }
        try await set(answer, on: b, local: true); try await gathered(b)
        try await set(try XCTUnwrap(b.localDescription), on: a, local: false)
    }
}

extension BridgedCallServiceTests {
    func testMissingTelephoneConfigurationCannotCreateOpenAIService() async {
        var created = 0
        let service = BridgedCallService(makeRealtime: { _ in created += 1; return FakeRealtimeService() },
            loadTelephone: { throw RealtimeError.configuration })
        do {
            try await service.start(definition: .init(phoneNumber: "09012345678", objective: "Test"),
                                    language: .spanish, configuration: .init(apiKey: "test", model: "test"))
            XCTFail("Expected configuration failure")
        } catch {}
        XCTAssertEqual(created, 0)
    }
    func testLateVADCannotMuteFinalGoodbyeButLiveInstructionsCan() throws {
        var interrupts = 0, starts = 0
        let client = OpenAIRealtimeClient(sendEvent: { _ in }, onAudioInterrupted: { interrupts += 1 }, onAudioStarted: { starts += 1 })
        defer { client.stop() }
        func event(_ value: [String: Any]) throws { client.receive(try JSONSerialization.data(withJSONObject: value)) }
        try event(["type": "input_audio_buffer.speech_started"])
        XCTAssertEqual(interrupts, 1)
        try event(["type": "response.done", "response": ["id": "end", "status": "completed", "output": [[
            "type": "function_call", "name": "end_session", "call_id": "end-tool",
            "arguments": "{\"reason\":\"recipient_requested_end\"}"
        ]]]])
        try event(["type": "output_audio_buffer.started", "response_id": "goodbye"])
        try event(["type": "input_audio_buffer.speech_started"])
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(interrupts, 1, "Late input events cannot mute a VAD-disabled goodbye")
        try client.submitInstruction(id: UUID(), text: "Wait, ask one more thing")
        XCTAssertGreaterThan(interrupts, 1)
    }
}
