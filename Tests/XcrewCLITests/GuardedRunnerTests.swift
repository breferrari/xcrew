import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

/// The golden guard sees a path however a command names it.
struct GuardedRunnerTests {
    @Test func everySpellingOfAPathIsSeen() async {
        let runner = GuardedRunner(base: FakeRunner())
        _ = await runner.run(["tool", "/abs/a", "--out=/abs/b", "-o/abs/c", "~/d", "sh", "-c", "cat '/abs/e' /abs/f"], stdin: Data("read /abs/g".utf8))
        #expect(Set(runner.outside(["/kept"])) == ["/abs/a", "/abs/b", "/abs/c", "~/d", "/abs/e", "/abs/f", "/abs/g"])
        #expect(runner.outside(["/abs"]) == ["~/d"])
    }
}
