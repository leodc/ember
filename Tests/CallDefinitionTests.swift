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

    func testWhitespaceDoesNotPermitReview() {
        let definition = CallDefinition(
            phoneNumber: "   ",
            objective: "Book a dental cleaning",
            agentLanguage: "Japanese"
        )

        XCTAssertFalse(definition.canReview)
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
        XCTAssertTrue(context.contains("ask_user is not available yet"))
        let session = RealtimeSessionContext.session(for: definition, userLanguage: .english, model: "test-model")
        XCTAssertEqual(session["model"] as? String, "test-model")
        XCTAssertEqual((session["tools"] as? [[String: Any]])?.first?["name"] as? String, "end_session")
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
