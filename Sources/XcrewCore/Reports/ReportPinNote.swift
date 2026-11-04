import Foundation

extension Report {
    /// That another Xcode than the project's pin built, for a failure whose errors another SDK or toolchain gives, and the
    /// pin it names, written as `pinNote` and `pin`.
    public struct PinNote: Sendable, Equatable {
        /// The note: which Xcode built, against which pin.
        public let note: String
        /// The pin it names, `26.5 (.xcode-version)`: the mod names each pin once a session, however the note is worded.
        /// Nil when the project names none.
        public let pin: String?

        public init(note: String, pin: String?) {
            self.note = note
            self.pin = pin
        }
    }
}
