import Foundation
import Testing
@testable import XcrewCore

/// A failed UI test's runs as `xcresulttool get test-results activities` lists them, in shapes the test bed's capture
/// doesn't hold.
@Suite struct FailedRunTests {
    /// One run on one device, with `activities` as its steps.
    static func activities(_ activities: String) -> String {
        #"{"testIdentifier":"LoginTests/testLogin()","testName":"testLogin()","testRuns":[{"device":{"deviceId":"D","deviceName":"Sim","architecture":"arm64","modelName":"iPhone 17","platform":"iOS Simulator","osVersion":"27.2"},"testPlanConfiguration":{"configurationId":"1","configurationName":"Test Scheme Action"},"activities":[\#(activities)]}]}"#
    }

    /// A failure inside a step of the test's own, such as `XCTContext.runActivity`: the step names it, and the steps
    /// before it lead up to it.
    @Test func aFailureInsideAStepIsFound() throws {
        let runs = try #require(FailedRun.runs(activities: Self.activities(#"""
            {"title":"Set Up","isAssociatedWithFailure":false,"startTime":1},
            {"title":"Open App","isAssociatedWithFailure":false,"startTime":2},
            {"title":"Log in","isAssociatedWithFailure":false,"startTime":3,"childActivities":[
              {"title":"Tap \"Email\" TextField","isAssociatedWithFailure":false,"startTime":3.5},
              {"title":"Failed to tap \"Log in\" Button: No matches found","isAssociatedWithFailure":true,"startTime":4}
            ]},
            {"title":"Tear Down","isAssociatedWithFailure":false,"startTime":5}
            """#)))
        let run = try #require(runs.first)
        #expect(run.steps == ["Set Up", "Open App", "Log in"])
        #expect(run.failure == #"Failed to tap "Log in" Button: No matches found"#)
        #expect(run.failedAt == 4)
    }

    /// A run keeps a recording when one of its steps holds an `.mp4` attachment, as XCTest names its recordings.
    @Test func aRunKnowsWhetherItKeptARecording() throws {
        let recorded = try #require(FailedRun.runs(activities: Self.activities(#"""
            {"title":"Start Test","isAssociatedWithFailure":false,"startTime":1,"attachments":[{"name":"Screen Recording 2026-10-30 at 03.53.22 PM.mp4","uuid":"U","lifetime":"keepAlways","timestamp":1}]},
            {"title":"XCTAssertTrue failed","isAssociatedWithFailure":true,"startTime":2}
            """#)))
        let unrecorded = try #require(FailedRun.runs(activities: Self.activities(#"{"title":"XCTAssertTrue failed","isAssociatedWithFailure":true,"startTime":2}"#)))
        #expect(recorded.map(\.hasRecording) == [true])
        #expect(unrecorded.map(\.hasRecording) == [false])
    }

    /// No answer, as `xcresulttool` gives when it fails, is not a run that passed.
    @Test func noAnswerIsNotNoFailure() {
        #expect(FailedRun.runs(activities: "") == nil)
        #expect(FailedRun.runs(activities: Self.activities(#"{"title":"Set Up","isAssociatedWithFailure":false,"startTime":1}"#)) == [])
    }
}
