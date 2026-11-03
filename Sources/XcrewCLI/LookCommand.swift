import Foundation
import XcrewCore

/// What a test run kept about each failed UI test's failure: the steps before it and the screen at it, per
/// configuration and device, from the project's newest MobileBuildMCP result bundle or one named. A test or bundle quoted
/// as a shell word, as the failure notes give them, is read as the value it quotes, an empty test as none: the `look`
/// tool passes them on with no shell to take the quotes off.
struct LookCommand: Command {
    let name = "look"
    let valuedOptions: Set<String> = ["bundle"]
    let takesWords = true
    let usage = [
        "look [<Suite/test>] [--bundle <path>]   a failed UI test's steps and the screen at its failure, per configuration and device: from MobileBuildMCP's newest test run, or a result bundle",
    ]

    static let noBundle = "xcrew: MobileBuildMCP has kept no test run for this project; pass --bundle <path> for another"

    func run(_ invocation: Invocation) async throws -> Int32 {
        let context = invocation.context
        guard invocation.arguments.positional.count <= 1 else { throw UsageError(description: "look takes one test at most (xcrew look --help)") }
        let given = invocation.arguments["bundle"]
        let named = Self.given(given)
        guard given == nil || named != nil else { throw UsageError(description: "look's --bundle names no result bundle (xcrew look --help)") }
        let newest = if named == nil { await ResultBundle.newest(project: context.project.root, machine: context.machine) } else { String?.none }
        guard let path = named ?? newest else {
            invocation.print(Self.noBundle)
            return 1
        }
        let bundle = ResultBundle(path: path, runner: context.runner)
        invocation.print(await Look.report(bundle: bundle, named: Self.given(invocation.arguments.positional.first), keptIn: context.machine.cacheFolder.appending(path: "images"), now: context.machine.now()))
        return 0
    }

    /// A word as given, without the quotes a shell would take off; none when it's empty.
    static func given(_ word: String?) -> String? {
        word.map(ShellWord.unquoted).flatMap { $0.isEmpty ? nil : $0 }
    }
}
