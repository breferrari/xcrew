import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The shared schemes that test only targets a change can break, each with what it tests and where it is.
@Suite struct SchemesTestingOnlyTests {
    let project = Project.temporary()

    func testingOnly(_ targets: Set<String>, in containers: [String] = ["App.xcodeproj"]) -> [TestSchemes.Scheme] {
        TestSchemes.testingOnly(targets, in: containers.map { project.root.appending(path: $0) }, from: project.root)
    }

    @Test func aSchemeTestingAnythingElseIsLeftOutAndEachNamesItsTargets() {
        project.writeScheme("Core", testing: ["CoreTests"])
        project.writeScheme("Kit", testing: ["KitTests", "KitUITests"])
        project.writeScheme("All", testing: ["CoreTests", "KitTests", "KitUITests", "AppTests"])
        #expect(testingOnly(["CoreTests", "KitTests", "KitUITests"]) == [
            .init(name: "Core", container: "App.xcodeproj", targets: ["CoreTests"]),
            .init(name: "Kit", container: "App.xcodeproj", targets: ["KitTests", "KitUITests"]),
        ])
    }

    /// Two projects may each have a scheme of one name: they test different targets and are kept apart.
    @Test func schemesOfOneNameInTwoProjectsAreKeptApart() {
        project.writeScheme("Tests", testing: ["ATests"], container: "A.xcodeproj", folder: "A.xcodeproj/xcshareddata")
        project.writeScheme("Tests", testing: ["BTests"], container: "B.xcodeproj", folder: "B.xcodeproj/xcshareddata")
        #expect(testingOnly(["ATests"], in: ["A.xcodeproj", "B.xcodeproj"]) == [.init(name: "Tests", container: "A.xcodeproj", targets: ["ATests"])])
    }

    /// A test plan that can't be read may test anything, so its scheme isn't one that tests only the selection.
    @Test func aSchemeWhosePlanCantBeReadIsLeftOut() {
        project.writeScheme("Core", testing: ["CoreTests"], plan: "Missing.xctestplan")
        #expect(testingOnly(["CoreTests"]).isEmpty)
    }
}
