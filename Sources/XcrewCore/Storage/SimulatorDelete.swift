import Foundation

/// What deleting a simulator costs, said before the `xcrun simctl delete` that ends the text offering it.
enum SimulatorDelete {
    /// "loses the apps installed on `them` and their data, so it's the person's to agree to", for `it` or `them`.
    static func loses(_ them: String) -> String {
        "loses the apps installed on \(them) and their data, so it's the person's to agree to"
    }
}
