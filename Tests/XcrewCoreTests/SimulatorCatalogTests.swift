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

    /// Xcode 27.2 beta 3 ships the iPhone Duo on a runtime of its own, `iOS-27-2-iPhone19-4`, which simctl says is 27.2.
    static let deviceSpecific = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"name":"iPhone 18 Pro","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"},{"name":"iPhone 17","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"}],"com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4":[{"name":"iPhone Duo","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"}]}}"#
    static let runtimes = #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-2","version":"27.2","platform":"iOS"},{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4","version":"27.2","platform":"iOS"}]}"#

    @Test func aDeviceSpecificRuntimeIsTheVersionSimctlSays() async {
        let simulators = SimulatorCatalog(json: Data(Self.deviceSpecific.utf8), runtimes: Data(Self.runtimes.utf8))
        #expect(simulators.defaultIPhone == "iPhone 17")
    }

    @Test func simctlsVersionWinsOverTheIdentifiers() async {
        let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"name":"iPhone 17","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-27-1-Beta":[{"name":"iPhone 18","isAvailable":true}]}}"#
        let runtimes = #"{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-2","version":"27.2","platform":"iOS"},{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-1-Beta","version":"27.3","platform":"iOS"},{"identifier":"com.apple.CoreSimulator.SimRuntime.broken"}]}"#
        #expect(SimulatorCatalog(json: Data(devices.utf8), runtimes: Data(runtimes.utf8)).defaultIPhone == "iPhone 18")
    }

    /// Without simctl's runtime list, a runtime's version is the leading numbers of its identifier, never the rest.
    @Test func anIdentifiersVersionStopsAtItsFirstWord() async {
        #expect(SimulatorCatalog(json: Data(Self.deviceSpecific.utf8)).defaultIPhone == "iPhone 17")
    }

    static let duoAndPro = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2":[{"name":"iPhone Duo","isAvailable":true,"deviceTypeIdentifier":"duo"},{"name":"iPhone Pro","isAvailable":true,"deviceTypeIdentifier":"pro"}]}}"#

    @Test func aDeviceWithTwoDisplaysIsNeverTheDefault() async {
        var simulators = SimulatorCatalog(json: Data(Self.duoAndPro.utf8))
        simulators.multiDisplayTypes = ["duo"]
        #expect(simulators.defaultIPhone == "iPhone Pro")
    }

    /// The doctor reads only the list; setup, choosing a default, reads which device types have two displays.
    @Test func choosingADefaultFindsTheDevicesWithTwoDisplays() async {
        let types = #"{"devicetypes":[{"identifier":"duo","bundlePath":"/Profiles/Duo.simdevicetype"},{"identifier":"pro","bundlePath":"/Profiles/Pro.simdevicetype"}]}"#
        let runner = FakeRunner(responses: [
            "xcrun simctl list devices available --json": .init(status: 0, stdout: Self.duoAndPro),
            "xcrun simctl list runtimes --json": .init(status: 0, stdout: Self.runtimes),
            "xcrun simctl list devicetypes --json": .init(status: 0, stdout: types),
            "plutil -extract capabilities.displays json -o - /Profiles/Duo.simdevicetype/Contents/Resources/capabilities.plist": .init(status: 0, stdout: #"[{"powerState":1},{"powerState":1},{"powerState":0}]"#),
            "plutil -extract capabilities.displays json -o - /Profiles/Pro.simdevicetype/Contents/Resources/capabilities.plist": .init(status: 0, stdout: #"[{"powerState":1},{"powerState":0}]"#),
        ])
        #expect(await SimulatorCatalog.load(using: runner, choosingADefault: true).defaultIPhone == "iPhone Pro")
        #expect(await SimulatorCatalog.load(using: runner).multiDisplayTypes.isEmpty)
    }

    /// A plain iPhone's CoreSimulator profile on this Mac, where `simctl list devicetypes` puts them.
    static let plainIPhoneProfile: String? = {
        let folder = "/Library/Developer/CoreSimulator/Profiles/DeviceTypes"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.sorted().first { $0.range(of: #"^iPhone \d+\.simdevicetype$"#, options: .regularExpression) != nil }.map { "\(folder)/\($0)" }
    }()

    /// Whether that profile lists its displays at all: Xcode 27's do, Xcode 26's (CI's runner) don't.
    static let profileListsDisplays: Bool = {
        struct Profile: Decodable {
            struct Capabilities: Decodable { let displays: [SimulatorCatalog.Display]? }
            let capabilities: Capabilities?
        }
        guard let plain = plainIPhoneProfile,
              let data = FileManager.default.contents(atPath: "\(plain)/Contents/Resources/capabilities.plist") else { return false }
        return (try? PropertyListDecoder().decode(Profile.self, from: data))?.capabilities?.displays != nil
    }()

    /// Pins the undocumented profile shape the catalog reads (docs/findings.md, *The simulator setup picks*), on
    /// this Mac's own Xcode: a platform change that moves or renames it turns this red.
    @Test(.enabled(if: profileListsDisplays))
    func aPlainIPhonesInstalledProfileHasOneBuiltInDisplay() async throws {
        let plain = try #require(Self.plainIPhoneProfile)
        let read = await SystemCommandRunner().run("plutil", "-extract", "capabilities.displays", "json", "-o", "-", "\(plain)/Contents/Resources/capabilities.plist")
        let displays = try JSONDecoder().decode([SimulatorCatalog.Display].self, from: Data(read.stdout.utf8))
        #expect(displays.filter { $0.powerState == 1 }.count == 1)
    }

    @Test func runtimeVersionsCompareNumerically() async {
        let simulators = catalog([
            "com.apple.CoreSimulator.SimRuntime.iOS-9-0": ["iPhone 6"],
            "com.apple.CoreSimulator.SimRuntime.iOS-10-0": ["iPhone 7"],
        ])
        #expect(simulators.defaultIPhone == "iPhone 7")
    }
}
