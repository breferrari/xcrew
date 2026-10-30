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
        let (project, machine) = (invocation.context.project, invocation.context.machine)
        let installed = await Xcodes.installed(on: machine)
        let pin = Xcodes.pin(of: project)
        let match = pin.flatMap { Xcodes.matching($0.version, in: installed) }
        if invocation.arguments.has("developer-dir") {
            guard pin != nil else { return Self.noPin }
            guard let match else { return Self.noMatch }
            invocation.print("\(match.path)/Contents/Developer")
            return 0
        }
        for install in installed { invocation.print("installed: Xcode \(install.version) (\(install.build)) at \(install.path)") }
        invocation.print("selected: \(await Xcodes.selected(on: machine).map { "Xcode \($0.version)" } ?? "none")")
        if let pin {
            invocation.print("pinned: Xcode \(pin.version) (\(pin.file)), \(match.map { "installed at \($0.path)" } ?? "not installed")")
        } else {
            invocation.print("pinned: none")
        }
        let builds = await Xcodes.forBuilds(of: project, on: machine).map { "Xcode \($0.version)" } ?? "the selected Xcode"
        let applied = if case .applied = Xcodes.launch(of: project, on: machine) { true } else { false }
        invocation.print("builds: \(builds)\(pin != nil && !applied ? ", since MobileBuildMCP started without the pin" : "")")
        let named = Xcodes.ci(of: project).compactMap { named in named.version.map { "Xcode \($0) (\(named.file):\(named.line))" } }
        invocation.print("CI: \(named.isEmpty ? "names no Xcode version" : named.joined(separator: ", "))")
        let open = await Xcodes.running(on: machine).map { "Xcode \($0.version)" }
        invocation.print("open: \(open.isEmpty ? "none" : open.joined(separator: ", "))")
        return 0
    }
}
