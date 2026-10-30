import Foundation

/// An app bundle on disk with the two plists xcrew reads an Xcode from, for a fake applications folder.
public enum FakeXcode {
    public static func install(in folder: URL, _ name: String, identifier: String = "com.apple.dt.Xcode", version: String, build: String?) {
        let contents = folder.appending(path: "\(name)/Contents")
        try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version]
        try! PropertyListEncoder().encode(info).write(to: contents.appending(path: "Info.plist"))
        if let build { try! PropertyListEncoder().encode(["ProductBuildVersion": build]).write(to: contents.appending(path: "version.plist")) }
    }
}

extension FakeXcode {
    /// The Mac most tests stand for: Xcode 27.2 beta 3 and Xcode 26.4 in `folder`.
    public static func installBoth(in folder: URL) {
        install(in: folder, "Xcode-27.2.0-Beta.3.app", version: "27.2", build: "27B5038j")
        install(in: folder, "Xcode-26.4.app", version: "26.4", build: "17E192")
    }
}
