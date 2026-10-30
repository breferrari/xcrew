import Foundation

extension ProcessList.Process {
    /// An xcodebuild, by `ps`'s program name or, when `comm` gave none, its command's path.
    var isXcodebuild: Bool { runs("xcodebuild") }

    /// Whether it runs `name`, by `ps`'s program name or, when `comm` gave none, its command's path.
    func runs(_ name: String) -> Bool {
        program == name || (program.isEmpty && command.split(separator: " ").first?.hasSuffix("/" + name) == true)
    }

    /// An xcodebuild that only answers a question, such as `-showBuildSettings` or `-list`, and opens no build folder.
    var asksOnly: Bool {
        command.contains(#/ -(show[A-Za-z]+|list|version|help|usage)(?= |$)/#)
    }

    /// Its `-destination`, which may hold spaces, up to the next flag.
    var destination: String? {
        command.firstMatch(of: #/-destination (.+?)(?= -[A-Za-z]|$)/#).map { String($0.1) }
    }

    /// Its `-derivedDataPath`, up to the next flag, spelled as the file system spells it.
    var derivedDataPath: String? {
        command.firstMatch(of: #/-derivedDataPath (.+?)(?= -[A-Za-z]|$)/#).map { ProjectLayout.canonicalPath(String($0.1)) }
    }

    /// Its `-workspace` or `-project`, up to the next flag, as given.
    var buildsFrom: String? {
        command.firstMatch(of: #/-(?:workspace|project) (.+?)(?= -[A-Za-z]|$)/#).map { String($0.1) }
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

extension ProcessList {
    /// The process that started `id`, past an `xcrun` that ran it: launchd's pid 1 once what started it exited.
    func starter(of id: Int32) -> Int32 {
        let above = ancestors(of: id)
        return above.first { !$0.runs("xcrun") }?.id ?? above.last?.parent ?? processes.first { $0.id == id }?.parent ?? 1
    }
}
