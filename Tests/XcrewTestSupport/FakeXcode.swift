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
