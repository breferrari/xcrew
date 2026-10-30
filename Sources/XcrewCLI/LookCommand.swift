import Foundation
import XcrewCore

/// What a test run kept about each failed UI test's failure: the steps before it and the screen at it, per
/// configuration and device, from the project's newest MobileBuildMCP result bundle or one named.
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
        let named = invocation.arguments["bundle"]
        let newest = if named == nil { await ResultBundle.newest(project: context.project.root, machine: context.machine) } else { String?.none }
        guard let path = named ?? newest else {
            invocation.print(Self.noBundle)
            return 1
        }
        // `Target/Suite/test`, as `-only-testing:` names it, is `Suite/test` in the result bundle; a name ending `()` is
        // the bundle's own, a nested suite's `/` included.
        let test = invocation.arguments.positional.first.map { named in
            let parts = named.split(separator: "/")
            return parts.count > 2 && !named.hasSuffix("()") ? TestID(suite: parts[parts.count - 2], name: parts[parts.count - 1]) : TestID(xcresultID: named)
        }
        let bundle = ResultBundle(path: path, runner: context.runner)
        invocation.print(await Look.report(bundle: bundle, test: test, keptIn: context.machine.cacheFolder.appending(path: "images")))
        return 0
    }
}
