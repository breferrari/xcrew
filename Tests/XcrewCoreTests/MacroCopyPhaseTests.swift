import Foundation
import Testing
@testable import XcrewCore
import XcrewTestSupport

/// The phase Tuist generated before 4.203, as it appears in a generated project file.
let oldTuistCopyPhase = ##"shellScript = "#  This build phase serves two purposes:\n#  - Force Xcode build system to compile the macOS executable transitively when compiling for non-macOS destinations\n    cp -f \"$BUILD_DIR/$CONFIGURATION/AMacros\" \"$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/AMacros\"\n";"##

@Suite struct MacroCopyPhaseTests {
    @Test func findsGeneratedProjectsThatCopyPluginsInPlace() {
        let project = Project.temporary(containing: ["Tuist"])
        project.write(oldTuistCopyPhase, to: "Packages/Macros/Macros.xcodeproj/project.pbxproj")
        project.write(oldTuistCopyPhase, to: "Tuist/.build/tuist-derived/Projects/SomeMacros/SomeMacros.xcodeproj/project.pbxproj")
        project.write("HEADER_SEARCH_PATHS = \"$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME\";", to: "App.xcodeproj/project.pbxproj")
        #expect(MacroCopyPhase.projects(in: project) == ["Macros", "SomeMacros"])
    }

    @Test func onlyATuistProjectIsSearched() {
        // Only Tuist generated the phase; elsewhere the walk over the tree would find nothing, slowly.
        let project = Project.temporary(containing: ["App.xcworkspace"])
        project.write(oldTuistCopyPhase, to: "Macros/Macros.xcodeproj/project.pbxproj")
        #expect(MacroCopyPhase.projects(in: project).isEmpty)
    }

    @Test func ignoresBuildOutputAndDependencies() {
        let project = Project.temporary(containing: ["Tuist"])
        project.write(oldTuistCopyPhase, to: ".build/checkouts/x/X.xcodeproj/project.pbxproj")
        project.write(oldTuistCopyPhase, to: "node_modules/y/Y.xcodeproj/project.pbxproj")
        #expect(MacroCopyPhase.projects(in: project).isEmpty)
    }

    @Test func theDoctorNamesTheProjectsAndTheFix() async {
        let project = Project.temporary(containing: ["App.xcworkspace", "Tuist"])
        project.write(oldTuistCopyPhase, to: "Macros/Macros.xcodeproj/project.pbxproj")
        let result = await MacroCopyPhaseCheck().run(.fake(project: project))
        #expect(result.status == .warn)
        #expect(result.message.contains("Macros") && result.message.contains("4.203"))
    }

    @Test func withAnOldTuistInstalledTheFixIsToUpgrade() async {
        let project = Project.temporary(containing: ["App.xcworkspace", "Tuist"])
        project.write(oldTuistCopyPhase, to: "Macros/Macros.xcodeproj/project.pbxproj")
        let runner = FakeRunner(installed: ["tuist"], responses: ["tuist version": .init(status: 0, stdout: "4.202.8\n")])
        let result = await MacroCopyPhaseCheck().run(.fake(runner, project: project))
        #expect(result.message.hasSuffix("Tuist 4.202.8 is installed: upgrade to 4.203 or later, then regenerate"))
    }

    @Test func withANewTuistInstalledOnlyRegeneratingIsLeft() async {
        let project = Project.temporary(containing: ["App.xcworkspace", "Tuist"])
        project.write(oldTuistCopyPhase, to: "Macros/Macros.xcodeproj/project.pbxproj")
        let runner = FakeRunner(installed: ["tuist"], responses: ["tuist version": .init(status: 0, stdout: "4.206.0\n")])
        let result = await MacroCopyPhaseCheck().run(.fake(runner, project: project))
        #expect(result.message.hasSuffix("Tuist 4.206.0 is installed, which no longer adds it: regenerate (tuist install, then tuist generate)"))
    }

    @Test func aProjectWithoutThePhasePasses() async {
        let project = Project.temporary(containing: ["App.xcodeproj"])
        #expect(await MacroCopyPhaseCheck().run(.fake(project: project)).status == .pass)
    }

}
