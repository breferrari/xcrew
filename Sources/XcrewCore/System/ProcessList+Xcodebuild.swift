import Foundation

extension ProcessList.Process {
    /// An xcodebuild, by `ps`'s program name or, when `comm` gave none, its command's path.
    var isXcodebuild: Bool {
        program == "xcodebuild" || command.split(separator: " ").first?.hasSuffix("/xcodebuild") == true
    }

    /// Its `-destination`, which may hold spaces, up to the next flag.
    var destination: String? {
        command.firstMatch(of: #/-destination (.+?)(?= -[A-Za-z]|$)/#).map { String($0.1) }
    }

    /// Its `-derivedDataPath`, up to the next flag.
    var derivedDataPath: String? {
        command.firstMatch(of: #/-derivedDataPath (.+?)(?= -[A-Za-z]|$)/#).map { String($0.1) }
    }

    /// How long it has run: `40 s`, `12 min`, `3 h`, `1 d 2 h`.
    var age: String {
        switch elapsed {
        case ..<60: "\(elapsed) s"
        case ..<3600: "\(elapsed / 60) min"
        case ..<86_400: "\(elapsed / 3600) h"
        default: "\(elapsed / 86_400) d \(elapsed % 86_400 / 3600) h"
        }
    }

    /// `pid 900, for <destination>, running 12 min`: an xcodebuild, as a note names it.
    var described: String {
        "pid \(id)" + (destination.map { ", for \($0)" } ?? "") + ", running \(age)"
    }
}
