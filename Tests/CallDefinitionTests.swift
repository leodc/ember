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
}

