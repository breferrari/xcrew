import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

@Suite struct SimulatorCatalogTests {
    func catalog(_ runtimes: [String: [String]]) -> SimulatorCatalog {
        let devices = runtimes.mapValues { $0.map { ["name": $0, "isAvailable": true] } }
        let json = try! JSONSerialization.data(withJSONObject: ["devices": devices])
        return SimulatorCatalog(json: json)
    }

    @Test func picksTheNewestPlainIPhoneOnTheNewestRuntime() async {
        let simulators = catalog([
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": ["iPhone 17", "iPhone 18"],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": ["iPhone 18 Pro", "iPhone 18", "iPhone 17", "iPad Air"],
            "com.apple.CoreSimulator.SimRuntime.watchOS-12-0": ["Apple Watch Series 11"],
        ])
        #expect(simulators.defaultIPhone == "iPhone 18")
    }

    @Test func fallsBackToAnyIPhoneOnTheNewestRuntime() async {
        let simulators = catalog(["com.apple.CoreSimulator.SimRuntime.iOS-27-0": ["iPhone 18 Pro Max", "iPhone 18 Pro"]])
        #expect(simulators.defaultIPhone == "iPhone 18 Pro")
    }

    @Test func noIPhoneMeansNoDefault() async {
        #expect(catalog(["com.apple.CoreSimulator.SimRuntime.iOS-27-0": ["iPad Pro"]]).defaultIPhone == nil)
        #expect(SimulatorCatalog(json: Data()).devices.isEmpty)
    }

    @Test func aSimulatorIsFoundByNameOnTheNewestRuntime() async {
        let json = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"name":"iPhone 17","udid":"OLD","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone 17","udid":"NEW","isAvailable":true}]}}"#
        let simulators = SimulatorCatalog(json: Data(json.utf8))
        #expect(simulators.udid(of: "iPhone 17") == "NEW")
        #expect(simulators.udid(of: "iPhone 99") == nil)
    }

    @Test func runtimeVersionsCompareNumerically() async {
        let simulators = catalog([
            "com.apple.CoreSimulator.SimRuntime.iOS-9-0": ["iPhone 6"],
            "com.apple.CoreSimulator.SimRuntime.iOS-10-0": ["iPhone 7"],
        ])
        #expect(simulators.defaultIPhone == "iPhone 7")
    }
}
