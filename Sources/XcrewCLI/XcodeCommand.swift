import Foundation
import XcrewCore

/// `xcrew xcode`: which Xcode is which for the project. With `--developer-dir`, the developer folder of the installed
/// Xcode its `.xcode-version` names, which `libexec/mobilebuildmcp-server` sets as MobileBuildMCP's `DEVELOPER_DIR`; its
/// exit status says why there's none.
struct XcodeCommand: Command {
    /// `--developer-dir`'s status when the project pins no Xcode.
    static let noPin: Int32 = 3
    /// `--developer-dir`'s status when no installed Xcode is the pinned one.
    static let noMatch: Int32 = 4

    let name = "xcode"
    let flags: Set<String> = ["developer-dir"]
    let usage = [
        "xcode [--developer-dir]           the installed Xcodes, the selected one, the project's pin, CI's and the open one",
        "                                  (--developer-dir: the pinned Xcode's developer folder alone)",
    ]

    func run(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        if invocation.arguments.has("developer-dir") {
            switch await Xcodes.pinned(in: context.project, on: context.machine) {
            case .none: return Self.noPin
            case .notInstalled: return Self.noMatch
            case let .installed(install):
                invocation.print(install.developerFolder)
                return 0
            }
        }
        let xcodes = await context.xcodes.value()
        for install in xcodes.installed { invocation.print("installed: \(install.label) (\(install.build)) at \(install.path)") }
        invocation.print("selected: \(xcodes.selected?.label ?? "none")")
        let builds = xcodes.forBuilds?.label ?? "the selected Xcode"
        switch xcodes.pinState {
        case .none:
            invocation.print("pinned: none")
            invocation.print("builds: \(builds)")
        case let .notInstalled(pin, file):
            invocation.print("pinned: Xcode \(pin) (\(file)), not installed")
            invocation.print("builds: \(builds)")
        case let .waiting(install, file):
            invocation.print("pinned: \(install.label) (\(file)), installed at \(install.path)")
            invocation.print("builds: \(install.label), when MobileBuildMCP starts")
        case let .applied(install, file):
            invocation.print("pinned: \(install.label) (\(file)), installed at \(install.path)")
            invocation.print("builds: \(builds)")
        case let .notApplied(install, file, _):
            invocation.print("pinned: \(install.label) (\(file)), installed at \(install.path)")
            invocation.print("builds: \(builds), since MobileBuildMCP started without the pin")
        }
        let named = xcodes.ci.map { "Xcode \($0.version) (\($0.file):\($0.line))" }
        invocation.print("CI: \(named.isEmpty ? "names no Xcode version" : named.joined(separator: ", "))")
        invocation.print("open: \(xcodes.open.isEmpty ? "none" : xcodes.open.map(\.label).joined(separator: ", "))")
        return 0
    }
}
