import XCTest
@testable import DiscreteData

class DiscreteDataTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(DiscreteData().text, "Hello, World!")
    }


    static var allTests : [(String, (DiscreteDataTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
