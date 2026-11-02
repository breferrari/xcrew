import Foundation

/// The project's `.xcode-version` names an installed Xcode, and MobileBuildMCP's server started with it. Without a pin it
/// passes: a pin to suggest is said on a failure it can explain (`XcodeFailureNotes`).
struct XcodePinCheck: Check {
    let id = "xcode/pin"
    let title = "The project's Xcode pin applies"
    /// For a failed MobileBuildMCP build, test or run: the Xcode building isn't the one the project pins, so a different SDK
    /// may be why, with what fixes it stated as a fact. Nothing when the pin applies or there's none.
    static func failureNote(_ xcodes: XcodeSnapshot, hasXcodes: Bool) -> String? {
        let using = xcodes.forBuilds?.label ?? "the selected Xcode"
        switch xcodes.pinState {
        case let .notInstalled(pin, file):
            return "xcrew: builds use \(using) while the project pins Xcode \(pin) (\(file)): a different SDK may be the cause. \(hasXcodes ? "`\(xcodesInstall(pin))` installs the pin's Xcode" : "The pin's Xcode \(pin) downloads from \(downloads)")"
        case let .notApplied(install, file, _):
            return "xcrew: MobileBuildMCP started without the project's pin, \(install.label) (\(file)), so it builds with \(using): a different SDK may be the cause. The pin takes effect once Claude Code restarts."
        case .none, .waiting, .applied:
            return nil
        }
    }

    /// Whether an error is one another SDK or toolchain gives, in its own words, where the pin may be the cause: a module
    /// another Swift compiled, a deployment target outside the range it supports, an SDK it can't find, a platform it
    /// doesn't know. An API newer than the deployment target, or a package's own minimum, is the code's.
    static func mayBeTheToolchain(_ error: String) -> Bool {
        error.contains(/compiled with Swift [\d.]+ cannot be imported|range of supported deployment target versions|SDK "[^"]+" cannot be located|[Uu]nable to find (?:a )?sdk|[Uu]nrecognized platform name/)
    }

    /// Where Apple offers every Xcode for download.
    static let downloads = "https://developer.apple.com/download/all/"

    /// The command that installs Xcode `pin` with xcodes.
    static func xcodesInstall(_ pin: String) -> String {
        "xcodes install \(pin)"
    }

    /// The command that installs a pinned Xcode: xcodes when it's on PATH, else Apple's download page.
    static func install(_ pin: String, hasXcodes: Bool) -> String {
        hasXcodes ? xcodesInstall(pin) : "install Xcode \(pin) from \(downloads)"
    }

    func run(_ context: CheckContext) async -> CheckResult {
        let xcodes = await context.xcodes.value()
        let using = xcodes.forBuilds?.label ?? "the selected Xcode"
        let pinned = xcodes.pin?.version ?? ""
        switch xcodes.pinState {
        case .none:
            return .pass("no pin")
        case let .notInstalled(pin, file):
            let install = Self.install(pin, hasXcodes: context.runner.which("xcodes") != nil)
            // Every mismatch is a warning: the Mac still builds, with another Xcode than the project expects.
            guard let builds = xcodes.forBuilds else {
                return .warn("the project pins Xcode \(pin) (\(file)), but no installed Xcode is \(pin), so MobileBuildMCP builds with \(using): \(install)").offThePrompt()
            }
            let lead = "builds use \(builds.label) while the project pins Xcode \(pin) (\(file))"
            if Version.major(of: pin) == nil || Version.major(of: pin) != Version.major(of: builds.version) {
                return .warn("\(lead), and a build may fail with another major version's SDK: \(install)").offThePrompt()
            }
            if Version(pin) > Version(builds.version) {
                return .warn("\(lead), and a build may fail where the code uses the newer SDK: \(install)").offThePrompt()
            }
            return .warn("\(lead); a minor or patch difference rarely matters except to match CI's diagnostics: optionally, \(install)").offThePrompt()
        case let .waiting(install, _):
            return .skip("MobileBuildMCP isn't running for this project; it starts with \(install.label)")
        case let .applied(install, _):
            return .pass("\(install.label), at \(install.path)")
        case let .notApplied(_, file, why):
            return .warn("the project pins Xcode \(pinned) (\(file)), but MobileBuildMCP started without it (\(why)), so it builds with \(using): restart Claude Code")
        }
    }
}
