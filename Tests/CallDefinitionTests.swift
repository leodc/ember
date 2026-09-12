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
