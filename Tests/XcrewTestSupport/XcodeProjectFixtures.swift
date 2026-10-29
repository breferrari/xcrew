import Foundation
import XcrewCore

extension Project {
    /// `project.pbxproj` in the plist form Xcode writes, one native target per name, each with its product type
    /// (`bundle.unit-test`) after `com.apple.product-type.`.
    public func writePBXProj(_ targets: [String: String], in container: String = "App.xcodeproj") {
        let objects = targets.sorted { $0.key < $1.key }.enumerated().map { index, target in
            "T\(index) = { isa = PBXNativeTarget; name = \(target.key); productType = \"com.apple.product-type.\(target.value)\"; };"
        }
        write("// !$*UTF8*$!\n{ archiveVersion = 1; objects = { \(objects.joined(separator: " ")) }; rootObject = T0; }\n", to: "\(container)/project.pbxproj")
    }

    /// A scheme whose test action runs `targets`, and optionally a test plan, laid out as Xcode writes one.
    public func writeScheme(_ name: String, testing targets: [String] = [], skipped: Bool = false, plan: String? = nil, container: String = "App.xcodeproj", folder: String = "App.xcodeproj/xcshareddata") {
        let testables = targets.map { target in
            "<TestableReference skipped = \"\(skipped ? "YES" : "NO")\"><BuildableReference BuildableIdentifier = \"primary\" BuildableName = \"\(target).xctest\" BlueprintName = \"\(target)\" ReferencedContainer = \"container:\(container)\"></BuildableReference></TestableReference>"
        }
        let plans = plan.map { "<TestPlans><TestPlanReference reference = \"container:\($0)\" default = \"YES\"></TestPlanReference></TestPlans>" } ?? ""
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Scheme LastUpgradeVersion = \"2700\" version = \"1.7\"><TestAction buildConfiguration = \"Debug\">\(plans)<Testables>\(testables.joined())</Testables></TestAction></Scheme>\n"
        write(xml, to: "\(folder)/xcschemes/\(name).xcscheme")
    }
}
