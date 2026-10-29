import Testing
@testable import App

@Test func seededFailure() {
    #expect(Greeting.text == "Goodbye", "The test bed's seeded failure")
}

@Test(.disabled("The test bed's seeded skip"))
func seededSkip() {}
