import Foundation
import Testing
import XcrewCore
import XcrewTestSupport

@Suite struct TestSchemesTests {
    let project = Project.temporary()

    func choose(_ container: String = "App.xcodeproj", preferring app: String? = nil) -> TestSchemes.Choice {
        TestSchemes.choose(in: project.root.appending(path: container), preferring: app)
    }

    @Test func theSchemeThatRunsUnitTestsIsChosen() {
        project.writePBXProj(["App": "application", "AppTests": "bundle.unit-test"])
        project.writeScheme("App", testing: ["AppTests"])
        #expect(choose() == .scheme("App"))
    }

    @Test func aProjectWithNoUnitTestsHasNone() {
        project.writePBXProj(["App": "application", "AppUITests": "bundle.ui-testing"])
        project.writeScheme("App", testing: ["AppUITests"])
        project.writeScheme("Plain")
        #expect(choose() == .none)
    }

    @Test func severalAreReportedForThePersonToChoose() {
        project.writePBXProj(["App": "application", "CoreTests": "bundle.unit-test", "KitTests": "bundle.unit-test"])
        project.writeScheme("Core", testing: ["CoreTests"])
        project.writeScheme("Kit", testing: ["KitTests"])
        #expect(choose() == .several(["Core", "Kit"]))
    }

    @Test func theAppSchemeWinsWhenItRunsUnitTests() {
        project.writePBXProj(["App": "application", "AppTests": "bundle.unit-test", "KitTests": "bundle.unit-test"])
        project.writeScheme("App", testing: ["AppTests"])
        project.writeScheme("Kit", testing: ["KitTests"])
        #expect(choose(preferring: "App") == .scheme("App"))
    }

    @Test func aSkippedTestableDoesntRun() {
        project.writePBXProj(["AppTests": "bundle.unit-test"])
        project.writeScheme("App", testing: ["AppTests"], skipped: true)
        #expect(choose() == .none)
    }

    @Test func aTestPlansTargetsCount() {
        project.writePBXProj(["AppTests": "bundle.unit-test"])
        project.writeScheme("App", plan: "App.xctestplan")
        project.write(#"{"testTargets":[{"target":{"containerPath":"container:App.xcodeproj","identifier":"T0","name":"AppTests"}}],"version":1}"#, to: "App.xctestplan")
        #expect(choose() == .scheme("App"))
    }

    /// Xcode 27.2's JSON project file, as apple/xcode-project-format 0.1.0 encodes a target.
    @Test func theJSONProjectFormatIsRead() {
        project.write(#"{"targets":[{"name":"App","id":"T0","product-type":"application"},{"name":"AppTests","id":"T1","product-type":"bundle.unit-test"}]}"#, to: "App.xcodeproj/project.xcproj")
        project.writeScheme("App", testing: ["AppTests"])
        #expect(choose() == .scheme("App"))
    }

    @Test func aTargetWhoseTypeCantBeReadIsNeverGuessed() {
        project.writePBXProj(["App": "application"])
        project.writeScheme("App", testing: ["Missing"])
        #expect(choose() == .unknown(["App"]))
    }

    /// Schemes under `xcuserdata` are one person's and aren't committed.
    @Test func userSchemesDontCount() {
        project.writePBXProj(["AppTests": "bundle.unit-test"])
        project.writeScheme("App", testing: ["AppTests"], folder: "App.xcodeproj/xcuserdata/me.xcuserdatad")
        #expect(choose() == .none)
    }

    @Test func aWorkspaceReadsTheProjectsItHolds() {
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:App.xcodeproj"></FileRef></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.writePBXProj(["AppTests": "bundle.unit-test"])
        project.writeScheme("App", testing: ["AppTests"])
        #expect(choose("App.xcworkspace") == .scheme("App"))
    }

    /// A scheme that's known to run unit tests is enough; another whose targets can't be read doesn't hide it.
    @Test func aKnownUnitTestSchemeWinsOverOneThatCantBeRead() {
        project.writePBXProj(["AppTests": "bundle.unit-test"])
        project.writeScheme("App", testing: ["AppTests"])
        project.writeScheme("Package", testing: ["PackageTests"])
        #expect(choose() == .scheme("App"))
    }

    /// Xcode nests a workspace's projects in groups, each `group:` path relative to the group around it.
    @Test func aProjectInAWorkspaceGroupIsFound() {
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><Group location = "group:Modules" name = "Modules"><FileRef location = "group:Core/App.xcodeproj"></FileRef></Group></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.writePBXProj(["AppTests": "bundle.unit-test"], in: "Modules/Core/App.xcodeproj")
        project.writeScheme("Core", testing: ["AppTests"], folder: "Modules/Core/App.xcodeproj/xcshareddata")
        #expect(choose("App.xcworkspace") == .scheme("Core"))
    }

    /// Two projects can each have a target called `Tests`; a testable's own container says which it is.
    @Test func aTargetIsTypedFromItsOwnProject() {
        project.write(#"<?xml version="1.0" encoding="UTF-8"?><Workspace version = "1.0"><FileRef location = "group:A.xcodeproj"></FileRef><FileRef location = "group:B.xcodeproj"></FileRef></Workspace>"#, to: "App.xcworkspace/contents.xcworkspacedata")
        project.writePBXProj(["Tests": "bundle.ui-testing"], in: "A.xcodeproj")
        project.writePBXProj(["Tests": "bundle.unit-test"], in: "B.xcodeproj")
        project.writeScheme("UI", testing: ["Tests"], container: "A.xcodeproj", folder: "A.xcodeproj/xcshareddata")
        project.writeScheme("Unit", testing: ["Tests"], container: "B.xcodeproj", folder: "B.xcodeproj/xcshareddata")
        #expect(choose("App.xcworkspace") == .scheme("Unit"))
    }
}
