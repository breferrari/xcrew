import XCTest
@testable import App

final class GreetingTests: XCTestCase {
    func testGreetingSaysHello() {
        XCTAssertEqual(Greeting.text, "Hello")
    }

    func testKnownBug() {
        XCTExpectFailure("The test bed's expected failure: the greeting isn't localized")
        XCTAssertEqual(Greeting.text, "Bonjour")
    }
}
