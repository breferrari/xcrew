import Foundation
import Synchronization
import XcrewCLI
import XcrewCore
import XcrewTestSupport

/// One `xcrew` run, captured.
struct Run {
    let status: Int32
    let output: [String]
    let errors: [String]

    init(_ argv: String..., context: CheckContext = .fake(), stdin: String = "") async {
        await self.init(argv: argv, context: context, stdin: stdin)
    }

    init(argv: [String], context: CheckContext = .fake(), stdin: String = "") async {
        let output = Mutex<[String]>([]), errors = Mutex<[String]>([])
        status = await CLI.run(
            argv, context: context, standardInput: { Data(stdin.utf8) },
            print: { line in output.withLock { $0.append(line) } },
            printError: { line in errors.withLock { $0.append(line) } }
        )
        self.output = output.withLock { $0 }
        self.errors = errors.withLock { $0 }
    }

    var text: String { output.joined(separator: "\n") }
}
