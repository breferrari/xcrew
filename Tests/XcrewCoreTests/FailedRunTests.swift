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
        #expect(Self.passed(activities, listing, test) == ["Light · iPhone 17, iOS 27.2"])
    }

    /// With several devices, the test list nests each device's result for a configuration: a pass on one device never
    /// vouches for a run on another that crashed without a marked step, so a configuration counts only when every result
    /// under it passed.
    @Test func onePassingDeviceDoesNotVouchForAnother() {
        let test = TestID(suite: "T", name: "t")
        let device = { (id: String, model: String) in #"{"deviceId":"\#(id)","deviceName":"\#(id)","architecture":"arm64","modelName":"\#(model)","platform":"iOS Simulator","osVersion":"27.2"}"# }
        let activities = #"{"testIdentifier":"T/t()","testName":"t()","testRuns":["# + [device("A", "iPhone 17"), device("B", "iPhone Air")].map {
            #"{"device":\#($0),"testPlanConfiguration":{"configurationId":"1","configurationName":"Light"},"activities":[{"title":"Check","isAssociatedWithFailure":false,"startTime":1}]}"#
        }.joined(separator: ",") + "]}"
        let listing = #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"T/t()","name":"t()","result":"Failed","children":[{"nodeType":"Test Plan Configuration","name":"Light","result":"Failed","children":[{"nodeType":"Device","name":"A","result":"Passed"},{"nodeType":"Device","name":"B","result":"Failed"}]}]}]}"#
        #expect(Self.passed(activities, listing, test) == [])
        let nested = #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"T/t()","name":"t()","result":"Failed","children":[{"nodeType":"Device","name":"A","result":"Passed","children":[{"nodeType":"Test Plan Configuration","name":"Light","result":"Passed"}]},{"nodeType":"Device","name":"B","result":"Failed","children":[{"nodeType":"Test Plan Configuration","name":"Light","result":"Failed"}]}]}]}"#
        #expect(Self.passed(activities, nested, test) == [])
    }

    /// Where a test passed, the way `look` reads it: the test list indexed once, then the test's activities.
    static func passed(_ activities: String, _ listing: String, _ test: TestID) -> [String] {
        FailedRun.read(activities: activities, passedUnder: FailedRun.passedConfigurations(of: ResultBundle.testCases(in: listing)[test] ?? []))?.passed ?? []
    }

    /// A device node that carries no result says nothing either way, and doesn't hide a pass.
    @Test func aDeviceWithoutAResultDoesNotHideAPass() {
        let listing = #"{"testNodes":[{"nodeType":"Test Case","nodeIdentifier":"T/t()","name":"t()","result":"Failed","children":[{"nodeType":"Test Plan Configuration","name":"Light","result":"Passed","children":[{"nodeType":"Device","name":"A"}]},{"nodeType":"Test Plan Configuration","name":"Dark","result":"Failed"}]}]}"#
        #expect(Self.passed(Self.runs([("Light", false), ("Dark", true)]), listing, TestID(suite: "T", name: "t")) == ["Light · iPhone 17, iOS 27.2"])
    }

    /// No answer, as `xcresulttool` gives when it fails, is not a run that passed.
    @Test func noAnswerIsNotNoFailure() {
        #expect(FailedRun.runs(activities: "") == nil)
        #expect(FailedRun.runs(activities: Self.activities(#"{"title":"Set Up","isAssociatedWithFailure":false,"startTime":1}"#)) == [])
    }
}
