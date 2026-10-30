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

    /// A run's own attachments, from every step of it, each once: XCTest lists one under each step it belongs to.
    @Test func aRunHoldsItsOwnAttachmentsOnce() throws {
        let runs = try #require(FailedRun.runs(activities: Self.activities(#"""
            {"title":"Start Test","isAssociatedWithFailure":false,"startTime":1,"attachments":[{"name":"Screen Recording.mp4","uuid":"R","lifetime":"keepAlways","timestamp":1}]},
            {"title":"Waiting for \"Hello\" StaticText","isAssociatedWithFailure":false,"startTime":2,"childActivities":[
              {"title":"Checking","isAssociatedWithFailure":false,"startTime":2.5,"attachments":[{"name":"Debug description","uuid":"D","lifetime":"keepAlways","timestamp":2.5}]}
            ],"attachments":[{"name":"Debug description","uuid":"D","lifetime":"keepAlways","timestamp":2.5}]},
            {"title":"XCTAssertTrue failed","isAssociatedWithFailure":true,"startTime":3,"attachments":[{"name":"App UI hierarchy for App","uuid":"H","lifetime":"keepAlways","timestamp":3.001}]}
            """#)))
        #expect(runs.first?.attachments == [
            FailedRun.Attachment(name: "Screen Recording.mp4", id: "R", at: 1),
            FailedRun.Attachment(name: "Debug description", id: "D", at: 2.5),
            FailedRun.Attachment(name: "App UI hierarchy for App", id: "H", at: 3.001),
        ])
    }

    /// Activities with one run per configuration named, failed or not.
    static func runs(_ runs: [(String, Bool)]) -> String {
        #"{"testIdentifier":"T/t()","testName":"t()","testRuns":["# + runs.map { name, failed in
            #"{"device":{"deviceId":"D","deviceName":"Sim","architecture":"arm64","modelName":"iPhone 17","platform":"iOS Simulator","osVersion":"27.2"},"testPlanConfiguration":{"configurationId":"1","configurationName":"\#(name)"},"activities":[{"title":"Check","isAssociatedWithFailure":\#(failed),"startTime":1}]}"#
        }.joined(separator: ",") + "]}"
    }

    /// The test list's result for each of a test's configurations, as `xcresulttool get test-results tests` gives them.
    static func listing(_ results: [(String, String)]) -> String {
        #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"T/t()","name":"t()","result":"Failed","children":["# + results.map { name, result in
            #"{"nodeType":"Test Plan Configuration","name":"\#(name)","nodeIdentifier":"1","result":"\#(result)"}"#
        }.joined(separator: ",") + "]}]}"
    }

    /// Where a test passed, each once however often it repeated: a configuration the test list says it passed under,
    /// never one where a run of it also failed, as a retry or another repetition can, nor one it was skipped under.
    @Test func whereItPassedIsWhatTheTestListSays() {
        let test = TestID(suite: "T", name: "t")
        let activities = Self.runs([("Light", false), ("Dark", true), ("Light", false), ("Dark", false), ("Sepia", false)])
        let listing = Self.listing([("Light", "Passed"), ("Dark", "Passed"), ("Sepia", "Skipped")])
        #expect(FailedRun.passed(activities: activities, listing: listing, of: test) == ["Light · iPhone 17, iOS 27.2"])
    }

    /// No answer, as `xcresulttool` gives when it fails, is not a run that passed.
    @Test func noAnswerIsNotNoFailure() {
        #expect(FailedRun.runs(activities: "") == nil)
        #expect(FailedRun.runs(activities: Self.activities(#"{"title":"Set Up","isAssociatedWithFailure":false,"startTime":1}"#)) == [])
    }
}
