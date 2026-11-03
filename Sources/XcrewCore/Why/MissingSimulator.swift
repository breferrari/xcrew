import Foundation

/// A build asked for a simulator by a name no simulator on the Mac has: one deleted, or gone with an Xcode update.
/// xcodebuild's wording, from the test bed's `captures/environment/simulator-missing`; MobileBuildMCP turns away a name
/// it can't place on a platform itself, with its own fix, so only a name like a device's reaches it.
struct MissingSimulator: MachineCause {
    func explanation(of failure: FailureEvidence) async -> String? {
        guard let name = name(in: failure) else { return nil }
        // A simulator by that name means something else kept the build from it, and a list that couldn't be read
        // shows nothing.
        let catalog = await SimulatorCatalog.load(using: failure.runner)
        guard !catalog.devices.isEmpty, !catalog.names.contains(name) else { return nil }
        return "no simulator here is named \(name), which the build asked for. /xcrew:setup writes the profiles again with simulators that are installed"
    }

    /// The simulator name the build asked for, from the destination specifier under the error.
    func name(in failure: FailureEvidence) -> String? {
        failure.errors(startingWith: "Unable to find a device matching the provided destination specifier")
            .lazy.flatMap(\.detail).compactMap { $0.firstMatch(of: #/name:([^,}]+?)\s*[,}]/#) }.first.map { String($0.1) }
    }
}
