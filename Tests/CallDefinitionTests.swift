import XCTest
@testable import AIPhoneAgent

final class CallDefinitionTests: XCTestCase {
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
