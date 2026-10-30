import Foundation
import Testing
@testable import XcrewCLI
@testable import XcrewCore

/// The plugin, the mcs techpack and the Swift code each name the same things: hooks, tools,
/// checks, prompts. These tests keep them in step, so a change in one place can't leave another
/// install path silently stale.
@Suite struct ManifestTests {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func text(_ path: String) throws -> String {
        try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8)
    }

    func json(_ path: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text(path).utf8)) as? [String: Any])
    }

    // MARK: Commands

    /// A skill named like the plugin takes the bare `/<plugin>` command, and Claude Code then
    /// refuses the mod's `$.command.register` for it at every session start.
    @Test func noSkillTakesTheModsCommand() throws {
        let plugin = try #require(try json(".claude-plugin/plugin.json")["name"] as? String)
        let skills = try FileManager.default.contentsOfDirectory(atPath: Self.repository.appending(path: "skills").path)
        #expect(!skills.contains(plugin))
        let mod = try text("hooks/mod/command.ts")
        #expect(mod.contains("name: '\(plugin)'"))
    }

    // MARK: Plugin hooks

    /// The spinner text reads like the rest of Claude Code; the hook's name already says it's Xcrew's.
    @Test func hookSpinnersCarryNoPrefix() throws {
        let hooks = try #require(try json("hooks/hooks.json")["hooks"] as? [String: [[String: Any]]])
        let messages = hooks.values.flatMap { $0 }.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["statusMessage"] as? String }
        #expect(!messages.isEmpty)
        #expect(messages.allSatisfy { !$0.hasPrefix("xcrew:") && $0.first?.isUppercase == true })
    }

    func hook(_ event: String) throws -> (matcher: String?, command: String) {
        let hooks = try #require(try json("hooks/hooks.json")["hooks"] as? [String: [[String: Any]]])
        let group = try #require(hooks[event]?.first)
        let handler = try #require((group["hooks"] as? [[String: Any]])?.first)
        return (group["matcher"] as? String, try #require(handler["command"] as? String))
    }

    @Test func sessionStartBriefsThroughTheCLI() async throws {
        #expect(try hook("SessionStart").command == #""${CLAUDE_PLUGIN_ROOT}/bin/xcrew" hook session-start"#)
    }

    @Test func sessionStartIsTheOnlyCommandHook() async throws {
        let hooks = try #require(try json("hooks/hooks.json")["hooks"] as? [String: Any])
        #expect(Array(hooks.keys) == ["SessionStart"])
    }

    @Test func hooksLoadTheMod() async throws {
        let modules = try #require(try json("hooks/hooks.json")["modules"] as? [String])
        #expect(modules == ["./mod/register.ts"])
        #expect(FileManager.default.fileExists(atPath: Self.repository.appending(path: "hooks/mod/register.ts").path))
    }

    /// mcs reads `techpack.yaml` strictly: a plain value holding `: ` is not valid YAML, and the whole
    /// pack fails to load. CI has no mcs to validate with, so this catches the usual way it breaks.
    @Test func techpackValuesWithAColonAreQuoted() throws {
        let unquoted = try text("techpack.yaml").components(separatedBy: "\n").filter {
            $0.contains(#/^\s*(?:- )?[\w-]+: (?!["'|>]).*: /#)
        }
        #expect(unquoted == [])
    }

    // MARK: MCP servers

    /// The failover note names only Xcode MCP tools the mod classifies, with the kind the note gives them.
    @Test(arguments: [("BuildProject", "build"), ("RunAllTests", "test")])
    func theFailoverNoteNamesToolsTheModKnows(tool: String, kind: String) throws {
        #expect(SessionBriefing.failoverNote(reason: "").contains("`\(tool)`"))
        #expect(try text("hooks/mod/tools.test.ts").contains("['mcp__xcode__\(tool)', '\(kind)']"))
    }

    /// The mod clears its stale mark on each command the CLI names for regenerating, as its tests feed it.
    @Test(arguments: [ProjectLayout.Generator.tuist, .xcodeGen], ["", "ios"])
    func theModRecognisesEachGenerateCommand(generator: ProjectLayout.Generator, path: String) throws {
        let manifests = ProjectLayout.Manifests(generator: generator, folder: URL(fileURLWithPath: "/"), path: path)
        let commands = generator == .tuist ? [manifests.generateCommand, manifests.installAndGenerateCommand] : [manifests.generateCommand]
        for command in commands {
            #expect(try text("hooks/mod/tools.test.ts").contains("'\(command)'"), "\(command)")
        }
    }

    /// After a generate, the mod clears the marks of the app it names, read back from the commands the CLI writes: each is
    /// a case of the mod's parser test, giving back the app's path, or none for the root.
    @Test(arguments: [ProjectLayout.Generator.tuist, .xcodeGen], ["", "ios"])
    func theModReadsTheAppBackFromEachCommand(generator: ProjectLayout.Generator, path: String) throws {
        let manifests = ProjectLayout.Manifests(generator: generator, folder: URL(fileURLWithPath: "/"), path: path)
        let commands = generator == .tuist ? [manifests.generateCommand, manifests.installAndGenerateCommand] : [manifests.generateCommand]
        for command in commands {
            #expect(try text("hooks/mod/tools.test.ts").contains("['\(command)', [\(path.isEmpty ? "undefined" : "'\(path)'")]]"), "\(command)")
        }
    }

    /// The mod asks the CLI about an edit only when the file's name is one a generator reads, as detection names them.
    @Test func theModAsksAboutEveryManifestName() throws {
        let tests = try text("hooks/mod/tools.test.ts")
        for name in ProjectLayout.tuistMarkers.map({ $0 == ProjectLayout.tuistFolder ? "\($0)/Package.swift" : $0 }) + ProjectLayout.tuistManifests + ProjectLayout.xcodeGenMarkers {
            #expect(tests.contains("'/a/\(name)'"), "\(name)")
        }
    }

    /// Every field of a failure the CLI reports is one the mod's type for it names: a field it doesn't name is one the
    /// ledger and the pane never read.
    @Test func theModsFailureTypeNamesEachFieldTheCLIReports() throws {
        let failure = ToolOutput.Failure(title: "T", message: "M", where: "W", isTest: true)
        let keys = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(failure)) as? [String: Any]).keys
        let items = try #require(try text("types/index.d.ts").firstMatch(of: /items: \{([^}]*)\}\[\]/)?.1)
        for key in keys {
            #expect(items.contains("\(key)?:") || items.contains("\(key):"), "types/index.d.ts doesn't name `\(key)`")
        }
    }

    /// The mod asks about an edit inside each bundle the CLI counts as an Xcode container, and inside Tuist's `Derived`
    /// folder, as the mod's tests feed its name filter.
    @Test func theModAsksAboutEveryFolderAGeneratorWrites() throws {
        let tests = try text("hooks/mod/tools.test.ts")
        for folder in Project.containerExtensions.map({ "App\($0)" }) + [ProjectLayout.derivedFolder] {
            #expect(tests.contains("'/a/\(folder)/"), "\(folder)")
        }
    }

    /// The routing rules send Claude to the affected tool before a full test run, by its name, with the guarantee it
    /// gives and when to run everything; the hook answering it matches the name it's registered under.
    @Test func theRoutingRulesAskTheAffectedToolAndNameItsGuarantee() throws {
        let routing = try text("context/routing.md")
        let affected = try text("hooks/mod/affected.ts")
        let plugin = try #require(try json(".claude-plugin/plugin.json")["name"] as? String)
        let name = try #require(affected.firstMatch(of: /export const AFFECTED_TOOL = \{\n  name: '(\w+)'/)?.1)
        #expect(affected.contains("export const AFFECTED_TOOL_NAME = 'mcp__\(plugin)__\(name)'"))
        #expect(routing.contains("`\(name)`"))
        #expect(routing.contains("as the project declares them, nothing more"))
        #expect(routing.contains("run the whole suite"))
    }

    /// The routing rules tell Claude how to repeat a test, with the flag the mod recognises a repeated run by, and none
    /// that stops at the first pass or failure, which can't tell flaky from real.
    @Test func theRoutingRulesRepeatATestTheWayTheModReadsIt() throws {
        let routing = try text("context/routing.md")
        #expect(routing.contains("\"-test-iterations\", \"5\", \"-test-repetition-relaunch-enabled\", \"YES\""))
        #expect(try text("hooks/mod/context.ts").contains("input.extraArgs.includes('-test-iterations')"))
        #expect(!routing.contains("-retry-tests-on-failure") && !routing.contains("-run-tests-until-failure"))
    }

    /// The loop budget's note sends Claude to the affected tool as the routing rules do, with the same promise to run
    /// the whole suite when it says so.
    @Test func theLoopNoteAndTheRoutingRulesAgreeOnTheAffectedTool() throws {
        let routing = try text("context/routing.md"), loop = try text("hooks/mod/loop.ts"), affected = try text("hooks/mod/affected.ts")
        let name = try #require(affected.firstMatch(of: /name: '([a-z-]+)'/)?.1)
        // The note names the tool by the constant; the routing rules by its name, behind ToolSearch.
        #expect(loop.contains(#"\`${AFFECTED_TOOL.name}\` tool (search for it)"#))
        #expect(routing.contains("`\(name)` tool (search for it)"))
        let promise = "When it says to run the whole suite"
        #expect(routing.contains(promise) && loop.contains(promise))
        #expect(routing.contains("`-only-testing:`") && loop.contains("`-only-testing:`"))
    }

    /// The MobileBuildMCP launcher reads the exit statuses the CLI's `xcode --developer-dir` and the shim's `--if-built`
    /// give, and waits no longer than its named limit.
    @Test func theLauncherReadsTheCLIsAndTheShimsStatuses() throws {
        let launcher = try text("libexec/mobilebuildmcp-server"), shim = try text("bin/xcrew")
        #expect(launcher.contains("\"$plugin/bin/xcrew\" --if-built xcode --developer-dir"))
        #expect(launcher.contains("\n        \(XcodeCommand.noPin)) outcome= ;;"))
        #expect(launcher.contains("\n        \(XcodeCommand.noMatch)) outcome=\"no match\" ;;"))
        #expect(shim.contains("[ -x \"$binary\" ] || exit 75") && launcher.contains("\n        75) outcome=\"not built\" ;;"))
        #expect(launcher.contains("\nPIN_SECONDS=2\n"))
    }

    /// The launcher writes its record where the doctor reads it, in the words it parses: xcrew's cache, as the shim and
    /// `Machine` name it, below `launches` at the project's real path.
    @Test func theLauncherRecordsWhatTheDoctorReads() throws {
        let launcher = try text("libexec/mobilebuildmcp-server"), shim = try text("bin/xcrew")
        let cache = #"${XCREW_CACHE:-"$HOME/Library/Caches/xcrew"}"#
        #expect(shim.contains("cache=\(cache)\n") && launcher.contains("record=\"\(cache)/launches$(pwd -P).launch\""))
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(Machine(environment: [:], home: home, runner: SystemCommandRunner()).cacheFolder.path == "/Users/someone/Library/Caches/xcrew")

        let folder = FileManager.default.temporaryDirectory.appending(path: "xcrew-record-\(UUID().uuidString)")
        let project = Project(root: folder.appending(path: "project"))
        try FileManager.default.createDirectory(at: project.root, withIntermediateDirectories: true)
        let machine = Machine(environment: ["XCREW_CACHE": folder.appending(path: "cache").path], home: folder, runner: SystemCommandRunner())
        #expect(Xcodes.launchRecord(of: project, on: machine).path == folder.appending(path: "cache").path + "/launches" + project.canonicalRoot + ".launch")
        let written: [(String, Xcodes.Launch)] = [("applied $developer", .applied("/Apps/X.app/Contents/Developer")), ("no match", .noMatch), ("not built", .notBuilt), ("timed out $PIN_SECONDS", .timedOut("2")), ("failed $status", .failed("1"))]
        for (outcome, launch) in written {
            #expect(launcher.contains("outcome=\"\(outcome)\""), "\(outcome)")
            let line = outcome.replacingOccurrences(of: "$developer", with: "/Apps/X.app/Contents/Developer").replacingOccurrences(of: "$PIN_SECONDS", with: "2").replacingOccurrences(of: "$status", with: "1")
            let record = Xcodes.launchRecord(of: project, on: machine)
            try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "\(line)\n".write(to: record, atomically: true, encoding: .utf8)
            #expect(Xcodes.launch(of: project, on: machine) == launch, "\(outcome)")
        }
    }

    /// The launcher's quick look for a pin passes over the folders the project walk leaves out, hidden ones too, and
    /// reaches one level below the deepest folder that can hold a container.
    @Test func theLauncherLooksForAPinWhereTheProjectWalkDoes() throws {
        let launcher = try text("libexec/mobilebuildmcp-server")
        let look = try #require(launcher.split(separator: "\n").first { $0.contains("-name .xcode-version") }.map(String.init))
        #expect(look.contains("-maxdepth \(ProjectLayout.searchDepth + 1) "))
        #expect(look.contains("-name '.?*'"))
        for folder in ProjectLayout.dependencyFolders { #expect(look.contains("-name \(folder) "), "\(folder)") }
        #expect(look.matches(of: /-name [A-Za-z]/).count == ProjectLayout.dependencyFolders.count)
    }

    /// The routing rules tell Claude how to turn coverage on, which the changed-line note needs, and what it costs, so
    /// it stays off the edit-and-test loop.
    @Test func theRoutingRulesTurnCoverageOnBeforeAPullRequest() throws {
        let routing = try text("context/routing.md")
        #expect(routing.contains("\"-enableCodeCoverage\", \"YES\""))
        #expect(routing.contains("it slows the run"))
    }

    /// The CLI decides flaky or real; the mod reads each verdict by the names the CLI writes, and no other.
    @Test func theModKnowsEveryVerdictTheCLIGives() throws {
        let union = try #require(try text("hooks/mod/cli.ts").firstMatch(of: /verdict: ('[^}]*?')\s*\}/)?.1)
        let names = Set(union.matches(of: /'(\w+)'/).map { String($0.1) })
        #expect(names == Set([ResultBundle.Verdict.flaky, .real, .passed, .none].map(\.rawValue)))
    }

    /// Each tool the mod defines is registered at session start and answered by a hook matching its full name.
    @Test(arguments: [("hooks/mod/ledger.ts", "LEDGER_TOOL"), ("hooks/mod/affected.ts", "AFFECTED_TOOL")])
    func eachToolOfTheModsIsRegisteredAndAnswered(file: String, tool: String) throws {
        let register = try text("hooks/mod/register.ts")
        #expect(try text(file).contains("export const \(tool)_NAME = "))
        #expect(register.contains("{ tool: \(tool)_NAME }"))
        #expect(try #require(register.firstMatch(of: /for \(const tool of \[([^\]]*)\]\) await quietly\(\(\) => \$\.tool\.register\(tool\)\)/)?.1).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(tool))
    }

    /// The hook answering the ledger tool matches the name Claude calls it by: `mcp__<plugin>__<name>`, from the plugin's
    /// name and the name the mod registers. A rename of either would leave every call unanswered.
    @Test func theLedgerToolsHookMatchesItsRegisteredName() throws {
        let ledger = try text("hooks/mod/ledger.ts")
        let plugin = try #require(try json(".claude-plugin/plugin.json")["name"] as? String)
        let name = try #require(ledger.firstMatch(of: /export const LEDGER_TOOL = \{\n  name: '(\w+)'/)?.1)
        #expect(ledger.contains("export const LEDGER_TOOL_NAME = 'mcp__\(plugin)__\(name)'"))
    }

    /// The plugin's MCP servers, by name, as the manifest declares them.
    func servers() throws -> [String: [String: Any]] {
        try #require(try json(".claude-plugin/plugin.json")["mcpServers"] as? [String: [String: Any]])
    }

    /// The plugin's root is this repository's, where Claude Code would read a `.mcp.json` as the project's own and find
    /// `${CLAUDE_PLUGIN_ROOT}` unset; the servers live in the manifest instead.
    @Test func theServersAreDeclaredInTheManifestNotAtTheRoot() {
        #expect(!FileManager.default.fileExists(atPath: Self.repository.appending(path: ".mcp.json").path))
    }

    @Test func marketplacePluginShipsTheThreeServers() async throws {
        let servers = try servers()
        #expect(Set(servers.keys) == ["MobileBuildMCP", "xcode", "sosumi"])

        let mobile = try #require(servers["MobileBuildMCP"])
        let arguments = try #require(mobile["args"] as? [String])
        #expect(arguments.contains("${CLAUDE_PROJECT_DIR}"), "MobileBuildMCP reads its config from its working directory")
        #expect((mobile["env"] as? [String: String])?["MOBILEBUILDMCP_SENTRY_DISABLED"] == "true")

        #expect(servers["sosumi"]?["url"] as? String == "https://sosumi.ai/mcp")
    }

    /// Claude Code strips a top-level field it doesn't know, and the directory flags it, so a misspelt field would do
    /// nothing in silence. These are the fields the manifest reference documents.
    static let manifestFields: Set = [
        "$schema", "name", "displayName", "version", "description", "author", "homepage", "repository", "license", "keywords",
        "metadata", "icon", "documentationUrl", "supportUrl", "privacyPolicyUrl", "termsOfServiceUrl", "defaultEnabled",
        "dependencies", "settings", "userConfig", "types", "channels", "skills", "commands", "agents", "hooks", "mcpServers",
        "lspServers", "outputStyles", "workflows", "experimental",
    ]

    @Test func marketplaceManifestUsesOnlyDocumentedFields() throws {
        let fields = Set(try json(".claude-plugin/plugin.json").keys)
        #expect(fields.subtracting(Self.manifestFields).isEmpty, "undocumented: \(fields.subtracting(Self.manifestFields).sorted())")
    }

    /// What the directory's listing shows and links to.
    @Test func listingNamesXcrewAndLinksToItsOwnPages() throws {
        let manifest = try json(".claude-plugin/plugin.json")
        #expect(manifest["displayName"] as? String == "Xcrew")
        #expect(manifest["documentationUrl"] as? String == "https://github.com/breferrari/xcrew#your-xcode-crew-inside-claude-code")
        #expect(manifest["supportUrl"] as? String == "https://github.com/breferrari/xcrew/issues")
    }

    // MARK: Anchors

    /// A heading's anchor as GitHub makes it: the words it shows (a link's text, not its URL), lowercased, with
    /// everything but letters, digits, spaces, hyphens and underscores dropped, and each space a hyphen.
    static func anchor(of heading: some StringProtocol) -> String {
        String(heading.drop { $0 == "#" }).replacing(/\[([^\]]*)\]\([^)]*\)/, with: { (link) -> String in String(link.1) })
            .trimmingCharacters(in: .whitespaces).lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
            .replacingOccurrences(of: " ", with: "-")
    }

    /// A Markdown file's anchors, from its headings outside code blocks.
    func anchors(in path: String) throws -> Set<String> {
        var anchors: Set<String> = []
        var inCode = false
        for line in try text(path).split(separator: "\n") {
            if line.hasPrefix("```") { inCode.toggle() }
            let level = line.prefix { $0 == "#" }.count
            guard !inCode, (1...6).contains(level), line.dropFirst(level).first == " " else { continue }
            anchors.insert(Self.anchor(of: line))
        }
        return anchors
    }

    /// GitHub's ids for headings in the README, docs and a skill, read from its rendered HTML on October 30, 2026,
    /// including bold and code markup.
    @Test(arguments: [
        ("### Your **Xcode** crew inside **Claude Code**.", "your-xcode-crew-inside-claude-code"),
        ("## Quick start", "quick-start"),
        ("### Test results Claude can act on", "test-results-claude-can-act-on"),
        ("### A guard for generated projects", "a-guard-for-generated-projects"),
        ("### Why `register.ts` holds every `$` call", "why-registerts-holds-every--call"),
        ("## SourceKit `No such module` errors", "sourcekit-no-such-module-errors"),
    ])
    func listingAnchorIsGitHubs(heading: String, id: String) {
        #expect(Self.anchor(of: heading) == id)
    }

    /// The Markdown files of the repository, which link to each other's headings.
    func markdownFiles() throws -> [String] {
        let root = Self.repository.path + "/"
        let enumerator = try #require(FileManager.default.enumerator(atPath: root))
        var files: [String] = []
        while let path = enumerator.nextObject() as? String {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if [".build", ".git", "node_modules", ".claude"].contains(name) || path.hasPrefix("Tests/XcrewCoreTests/Fixtures") { enumerator.skipDescendants(); continue }
            if path.hasSuffix(".md") { files.append(path) }
        }
        return files.sorted()
    }

    /// A link to a heading, in the same file or another of the repository's, goes nowhere unless the heading is there.
    @Test func listingLinksToHeadingsLandOnOne() throws {
        let files = try markdownFiles()
        #expect(files.contains("README.md") && files.contains("docs/architecture.md"))
        var checked = 0
        for file in files {
            let folder = (file as NSString).deletingLastPathComponent
            for link in try text(file).matches(of: /\]\(([^)\s:]*)#([^)\s]+)\)/) {
                let target = link.1.isEmpty ? file : ((folder as NSString).appendingPathComponent(String(link.1)) as NSString).standardizingPath
                #expect(try anchors(in: target).contains(String(link.2)), "\(file): \(link.1)#\(link.2) names no heading")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    /// The directory's listing links to the README's top and its privacy section.
    @Test(arguments: ["documentationUrl", "privacyPolicyUrl"])
    func listingLinksLandOnREADMEHeadings(_ field: String) throws {
        let link = try #require(try json(".claude-plugin/plugin.json")[field] as? String)
        let fragment = try #require(link.firstMatch(of: /^https:\/\/github\.com\/breferrari\/xcrew#(.+)$/)).1
        #expect(try anchors(in: "README.md").contains(String(fragment)), "\(link) names no README heading")
    }

    /// The directory reads a server started as a file of the plugin with plain arguments, not through a shell's `-c`.
    @Test(arguments: [("MobileBuildMCP", "libexec/mobilebuildmcp-server", ["${CLAUDE_PROJECT_DIR}"]), ("xcode", "libexec/xcode-mcp-server", nil)])
    func marketplaceLocalServerStartsFromThePluginsScript(server: String, script: String, arguments: [String]?) throws {
        let servers = try servers()
        let entry = try #require(servers[server])
        #expect(entry["command"] as? String == "${CLAUDE_PLUGIN_ROOT}/\(script)")
        if let arguments { #expect(entry["args"] as? [String] == arguments) } else { #expect(entry["args"] == nil) }
        #expect(FileManager.default.isExecutableFile(atPath: Self.repository.appending(path: script).path))
    }

    // MARK: CI

    /// The channels the Distribution job checks, one step each, as `scripts/distribution.sh` names them.
    func distributionChannels() -> [String] {
        let script = (try? text("scripts/distribution.sh")) ?? ""
        return script.matches(of: /^  ([a-z]+)\)$/.anchorsMatchLineEndings()).map { String($0.1) }
    }

    /// Each Distribution step runs its channel's tests by their name's prefix, so each channel has some, and every test
    /// of a file only one channel ships carries that channel's prefix.
    @Test func eachDistributionStepRunsItsChannelsTests() throws {
        let channels = distributionChannels()
        #expect(channels == ["marketplace", "listing", "techpack"])
        let source = try text("Tests/ManifestTests/ManifestTests.swift")
        let tests = source.matches(of: /func (\w+)\(/).map { String($0.1) }
        for channel in channels {
            #expect(tests.contains { $0.hasPrefix(channel) }, "no \(channel)… test for the \(channel) step")
        }
        let workflow = try text(".github/workflows/ci.yml")
        for channel in channels {
            #expect(workflow.contains("scripts/distribution.sh \(channel)"), "ci.yml has no step for \(channel)")
        }
        // A test reading the techpack's own files is the techpack step's.
        let bodies = source.split(separator: "\n    @Test").dropFirst()
        for body in bodies where body.contains("text(\"techpack.yaml\")") || body.contains("\"mcs/") {
            let name = body.firstMatch(of: /func (\w+)\(/).map { String($0.1) } ?? ""
            #expect(name == "eachDistributionStepRunsItsChannelsTests" || name.hasPrefix("techpack"), "\(name) reads the techpack's files")
        }
    }

    /// The toolchain `Package.swift` promises is the one a CI job tests: the floor job picks Xcode by the Swift version
    /// it reports, read from `swift-tools-version`, never by an Xcode name that ages.
    @Test func ciTestsTheSwiftToolsVersionFloor() throws {
        let ci = try text(".github/workflows/ci.yml")
        let floor = try #require(ci.firstMatch(of: /(?s)\n  swift-floor:\n.*?(?=\n  [a-z-]+:\n|\z)/)).output
        #expect(floor.contains("swift-tools-version"), "the floor job reads its version from Package.swift")
        #expect(floor.contains("swift --version"))
        #expect(!floor.contains(/Xcode_\d/), "an Xcode named by version")
        #expect(floor.contains("swift test"))
    }

    /// The ruleset and the release require one check, `CI`, which needs every other job: adding or renaming a job never
    /// touches them, and a job left out of `needs` fails here.
    @Test func oneCheckNeedsEveryJob() throws {
        let ci = try text(".github/workflows/ci.yml")
        let jobs = Set(ci.matches(of: /(?m)^  ([a-z][a-z-]*):$/).map { String($0.1) })
        let aggregate = try #require(ci.firstMatch(of: /(?s)\n  ci:\n(.*?)(?=\n  [a-z-]+:\n|\z)/)).output.1
        #expect(aggregate.contains("name: CI\n"))
        #expect(aggregate.contains("if: always()"))
        #expect(aggregate.contains("runs-on: ubuntu-latest"))
        #expect(!aggregate.contains("checkout"), "it reads results only")
        let needs = try #require(aggregate.firstMatch(of: /needs: \[([^\]]*)\]/)).output.1
        #expect(Set(needs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) == jobs.subtracting(["ci"]))
        #expect(aggregate.contains(#".changes.result == "success""#), "a failed changes job must fail CI, not skip everything")
        let release = try text(".github/workflows/release.yml")
        let checks = try #require(release.firstMatch(of: /for check in ([^;]+); do/)).output.1
        #expect(checks.trimmingCharacters(in: .whitespaces) == #""CI""#)
    }

    /// Every job that builds Swift says which toolchain it used, so a failure on CI names the compiler that said no.
    @Test func everySwiftJobLogsItsToolchain() throws {
        for workflow in [".github/workflows/ci.yml", ".github/workflows/canary.yml"] {
            let text = try text(workflow)
            #expect(text.matches(of: /swift test/).count <= text.matches(of: /swift --version/).count, "\(workflow)")
        }
    }

    /// The README's band picture is drawn by `assets/mockups.py`, which can't import the mod. It follows the mod's
    /// colour rule (only the ` · ` separators are faint) through one `SEP` that names the same text and theme key.
    @Test func theBandMockupDrawsTheModsColourRule() throws {
        let script = try text("assets/mockups.py")
        let mod = try text("hooks/mod/band.ts")
        #expect(script.contains(#"SEP = (" · ", "subtle")"#))
        #expect(mod.contains("const SEPARATOR = segment(' · ', 'subtle')"))
        let band = try #require(script.firstMatch(of: /(?s)def band\(\):.*?\n\n\n/)).output
        #expect(!band.contains(#""subtle")"#), "a value drawn faint in the band mockup")
    }

    /// The running line's time and time left add up to the usual time the passing line shows beside it.
    @Test func theBandMockupsRunningLineAgreesWithItsHistory() throws {
        let band = try #require(try text("assets/mockups.py").firstMatch(of: /(?s)def band\(\):.*?\n\n\n/)).output
        let seconds = { (clock: Substring) -> Int in
            let parts = clock.split(separator: ":").compactMap { Int($0) }
            return parts[0] * 60 + parts[1]
        }
        let elapsed = try #require(band.firstMatch(of: /"WHILE IT RUNS".*?\("(\d+:\d\d)", "text"\)/)).output.1
        let left = try #require(band.firstMatch(of: /"~(\d+:\d\d) left"/)).output.1
        let usual = try #require(band.firstMatch(of: /"WHEN IT PASSES".*?\(avg (\d+:\d\d)\)/)).output.1
        #expect(seconds(elapsed) + seconds(left) == seconds(usual), "\(elapsed) + \(left) isn't the usual \(usual)")
    }

    /// Each README picture shows in the reader's theme: a `<picture>` whose light and dark sources and dark fallback are
    /// this repository's files, by absolute URL, since the plugin directory's listing shows the README away from the
    /// repository. The light file is the dark one's `-light` twin from `assets/mockups.py --light`.
    @Test func listingPicturesFollowTheReadersTheme() throws {
        let readme = try text("README.md")
        let raw = "https://raw.githubusercontent.com/breferrari/xcrew/main/"
        let pictures = readme.matches(of: /(?s)<picture>(.*?)<\/picture>/).map { String($0.1) }
        #expect(pictures.count == 5)
        for picture in pictures {
            let light = try #require(picture.firstMatch(of: /media="\(prefers-color-scheme: light\)" srcset="([^"]+)"/)).output.1
            let dark = try #require(picture.firstMatch(of: /media="\(prefers-color-scheme: dark\)" srcset="([^"]+)"/)).output.1
            let fallback = try #require(picture.firstMatch(of: /<img src="([^"]+)" alt="[^"]+"/)).output.1
            #expect(fallback == dark, "\(fallback) isn't the dark source")
            #expect(light == dark.replacingOccurrences(of: ".png", with: "-light.png"), "\(light) isn't \(dark)'s light twin")
            for source in [light, dark] {
                #expect(source.hasPrefix(raw + "assets/"), "\(source) isn't one of this repository's assets by absolute URL")
                #expect(FileManager.default.fileExists(atPath: Self.repository.appending(path: String(source.dropFirst(raw.count))).path), "\(source) doesn't exist")
            }
        }
        // Outside the pictures, only the badges are images.
        let others = readme.replacing(/(?s)<picture>.*?<\/picture>/, with: "").matches(of: /!\[[^\]]*\]\(([^)\s]+)/).map { String($0.1) }
        #expect(others.allSatisfy { $0.hasPrefix("https://img.shields.io/") }, "\(others)")
    }

    /// A README section: from its heading to the next heading at its level or above.
    func readmeSection(_ heading: String) throws -> Substring {
        let readme = try text("README.md")
        let start = try #require(readme.range(of: "\n\(heading)\n")).upperBound
        let level = heading.prefix { $0 == "#" }.count
        let end = readme[start...].ranges(of: "\n#").map(\.upperBound).first { hash in
            let hashes = readme[hash...].prefix { $0 == "#" }.count + 1
            return hashes <= level && readme[readme.index(hash, offsetBy: hashes - 1)...].first == " "
        }
        return readme[start..<(end ?? readme.endIndex)]
    }

    /// A row of a table in the README's Privacy section, under the part that names who does it (`**The mod**`, `**The CLI**`).
    func privacyRow(_ row: String, of part: String) throws -> String {
        let privacy = try readmeSection("### Privacy")
        let after = try #require(privacy.range(of: "**\(part)**")).upperBound
        let rows = privacy[after...].matches(of: /\n\| \*\*([^*]+)\*\* \| ([^\n]+)/)
        return try #require(rows.first { $0.1 == row }.map { String($0.2) }, "no \(row) row under \(part)")
    }

    /// Privacy names every program the CLI starts: each one its source runs by name.
    @Test func listingPrivacyNamesEveryProgramTheCLIStarts() throws {
        let sources = try FileManager.default.subpathsOfDirectory(atPath: Self.repository.appending(path: "Sources").path).filter { $0.hasSuffix(".swift") }
        let programs = try Set(sources.flatMap { file in
            try text("Sources/\(file)").matches(of: /\.run\(\[?"([\w.-]+)"/).map { String($0.1) }
        })
        #expect(programs.isSuperset(of: ["xcrun", "git", "curl"]))
        let starts = try privacyRow("Starts", of: "The CLI")
        for program in programs {
            #expect(starts.contains("`\(program)"), "Privacy doesn't say why the CLI starts \(program)")
        }
    }

    /// Privacy names every event the mod hooks.
    @Test func listingPrivacyNamesEveryEventTheModHooks() throws {
        let events = Set(try text("hooks/mod/register.ts").matches(of: /on\('([a-z.]+)'/).map { String($0.1) })
        #expect(events.contains("tool.call"))
        let hooks = try privacyRow("Hooks", of: "The mod")
        for event in events {
            #expect(hooks.contains("`\(event)`"), "Privacy doesn't say what the mod's \(event) hook does")
        }
    }

    /// What Privacy says of each value the mod keeps: in Claude Code's store across sessions, by its key's prefix, and in
    /// the session's state, by its atom's key.
    static let keptValues = [
        "durations": "each build, test and run's recent durations",
        "updated": "when each last ran",
        "where": "the folder each last ran in",
        "tests": "how many tests each test run ran",
        "logs": "whether its server writes a log to follow",
        "ledger": "red-to-green ledger of tests",
        "run": "the run in progress",
        "loop": "the recent whole-suite runs the loop budget counts",
        "failures": "the last failing run's failures",
        "problems": "the doctor's latest problems",
        "build": "which build of the CLI to run",
        "row": "each build or test result's row",
        "stale": "the generate command a manifest edit is waiting on",
    ]

    /// Privacy names every value the mod keeps.
    @Test func listingPrivacyNamesEveryValueTheModKeeps() throws {
        let register = try text("hooks/mod/register.ts")
        let atoms = register.matches(of: /atom\(\{ plugin: 'xcrew', key: '(\w+)' \}/).map { String($0.1) }
        let modules = try ["timing", "ledger"].map { try text("hooks/mod/\($0).ts") }.joined()
        let prefixes = modules.matches(of: /`(\w+)\.\$\{|_PREFIX = '(\w+)\.'/).map { String($0.1 ?? $0.2 ?? "") }
        #expect(atoms.contains("stale") && prefixes.contains("ledger"))
        #expect(Set(atoms + prefixes) == Set(Self.keptValues.keys))
        let reads = try privacyRow("Reads", of: "The mod")
        for (key, said) in Self.keptValues {
            #expect(reads.contains(said), "Privacy doesn't say the mod keeps \(key): \(said)")
        }
    }

    /// The README's doctor report lists the doctor's checks, in the order the doctor prints them.
    @Test func listingDoctorReportListsEveryCheck() throws {
        let report = try #require(try text("README.md").firstMatch(of: /(?s)```\n(ok    mobilebuildmcp\/version.*?)```/)).1
        let listed = report.split(separator: "\n").compactMap { $0.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first.map(String.init) }
        #expect(listed == Doctor.checks.map(\.id))
    }

    /// The README names each of the CLI's commands in what it says of how Xcrew works.
    @Test func listingHowItWorksNamesEveryCommand() throws {
        let table = try readmeSection("## How it works")
        for command in CLI.commands {
            #expect(table.contains("`\(command.name)`") || table.contains("`xcrew \(command.name)"), "How it works doesn't name \(command.name)")
        }
    }

    /// Nothing in the README or the contributing guide pipes a download into a shell.
    @Test(arguments: ["README.md", "CONTRIBUTING.md"])
    func listingRunsNoDownload(_ file: String) throws {
        #expect(try text(file).firstMatch(of: /(curl|wget)[^\n|]*\|\s*(sudo\s+)?(ba|z)?sh\b/) == nil)
    }

    @Test func everyFlagACommandReadsIsDeclared() throws {
        for command in CLI.commands {
            let file = "Sources/XcrewCLI/\(String(describing: type(of: command))).swift"
            let read = try text(file).matches(of: /arguments\.has\("([\w-]+)"\)/).map { String($0.1) }
            #expect(Set(read).isSubset(of: command.flags), "\(file) reads \(Set(read).subtracting(command.flags).sorted())")
        }
    }

    /// The briefing keeps Claude off DerivedData, and its line on `xcodebuild` and `simctl` names only simulator tools
    /// the setup's config enables, so it never points at a tool that isn't there.
    @Test func routingKeepsClaudeOffDerivedDataAndOnTheEnabledTools() throws {
        let routing = try text("context/routing.md")
        #expect(routing.contains("- **DerivedData:** never delete it unless the person asks."))
        let bash = try #require(routing.split(separator: "\n").first { $0.hasPrefix("- **`xcodebuild` and `simctl` through Bash:**") })
        let named = Set(bash.matches(of: /`([a-z]+_[a-z_]+)`/).map { String($0.1) })
        #expect(!named.isEmpty)
        #expect(named.isSubset(of: Set(ConfigRenderer.simEnvTools)), "\(named.subtracting(ConfigRenderer.simEnvTools).sorted())")
    }

    /// Every run of the Swift tests in CI (both Swift jobs, and the canary's) checks the test bed out, at one commit,
    /// named in full: a tag can move, and there a missing checkout fails `ciHasTheTestBed`.
    @Test func everySwiftTestRunPinsTheSameTestBed() throws {
        let workflows = [try text(".github/workflows/ci.yml"), try text(".github/workflows/canary.yml")]
        let pins = workflows.flatMap { $0.matches(of: /repository: breferrari\/xcrew-testbed\n\s+ref: ([0-9a-f]+)/).map { String($0.1) } }
        #expect(pins.count == 3)
        #expect(Set(pins).count == 1)
        #expect(pins.allSatisfy { $0.count == 40 })
        let runs = workflows.map { $0.components(separatedBy: "XCREW_TESTBED: ${{ github.workspace }}/xcrew-testbed").count - 1 }
        #expect(runs == [2, 1])
    }

    /// Only the weekly canary can tell a `stable` still settling after a release from one left behind, and only the
    /// newest Claude Code can say xcrew still reads its saved-result notice, whose wording isn't documented, and still
    /// updates a plugin that follows a branch by its version.
    @Test(arguments: ["scripts/stable-check.sh ", "scripts/saved-notice.sh ", "scripts/stable-follows.sh "])
    func theCanaryRunsEachUpstreamCheck(_ script: String) throws {
        #expect(try text(".github/workflows/canary.yml").contains(script))
    }

    /// The mod drops history no run has updated for as long as the shim keeps a build no checkout has run.
    @Test func historyIsKeptAsLongAsAnUnusedBuild() throws {
        let kept = try #require(try text("hooks/mod/timing.ts").firstMatch(of: /HISTORY_KEPT_MS = (\d+) \* 24 \* 60 \* 60_000/)?.1)
        let shim = try #require(try text("bin/xcrew").firstMatch(of: /-mtime \+(\d+)/)?.1)
        #expect(kept == shim)
    }

    /// The band puts the doctor's restart warning first and keeps it until done, by that check's id.
    @Test func theModKnowsTheRestartCheck() throws {
        #expect(try text("hooks/mod/problems.ts").contains("export const RESTART_CHECK = '\(ConfigLoadedCheck().id)'"))
    }

    /// The setup skill takes the container from `xcrew project --setup` instead of searching, by the answer's own keys.
    @Test func theSetupSkillAsksTheCLI() throws {
        let skill = try text("skills/setup/SKILL.md")
        let answer = ProjectCommand.Answer(isGenerated: false, container: "A.xcworkspace", containerProblem: "why")
        let keys = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(answer)) as? [String: Any]).keys
        #expect(skill.contains("`xcrew project --setup`"))
        for key in keys where key != "isGenerated" {
            #expect(skill.contains("`\(key)`"), "the skill doesn't name `\(key)`")
        }
    }

    /// The setup skill hands Claude a command line; an option `xcrew setup` doesn't declare would be refused.
    @Test func theSetupSkillPassesOnlyOptionsSetupDeclares() throws {
        let line = try #require(try text("skills/setup/SKILL.md").firstMatch(of: /`xcrew setup [^`]*`/)?.0)
        let options = Set(line.matches(of: /--([\w-]+)/).map { String($0.1) })
        #expect(!options.isEmpty)
        #expect(options.isSubset(of: SetupCommand().valuedOptions.union(SetupCommand().flags)), "\(options.subtracting(SetupCommand().valuedOptions).sorted())")
    }

    /// The mod runs the CLI with options of its own; one a command doesn't declare would be refused, and the mod
    /// would quietly lose that answer.
    @Test func everyOptionTheModPassesIsDeclared() throws {
        let folder = Self.repository.appending(path: "hooks/mod")
        let sources = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".ts") && !$0.hasSuffix(".test.ts") }
        var calls = 0
        for source in sources {
            for line in try text("hooks/mod/\(source)").components(separatedBy: "\n") {
                guard let name = line.firstMatch(of: /\[\s*'([\w-]+)'/)?.1, let command = CLI.commands.first(where: { $0.name == name }) else { continue }
                calls += 1
                for option in line.matches(of: /'--([\w-]+)'/).map({ String($0.1) }) {
                    #expect(command.valuedOptions.contains(option) || command.flags.contains(option), "\(source): xcrew \(name) --\(option)")
                }
            }
        }
        #expect(calls >= 4, "found no CLI calls in the mod; the pattern no longer matches how it builds them")
    }

    // MARK: mcs techpack

    /// Checks the techpack leaves out because mcs does the same itself: `mcs check-updates` says when a
    /// pack has a newer version, with `mcs update` as the fix.
    static let coveredByMCS: Set = ["xcrew/up-to-date"]

    @Test func techpackHasEveryDoctorCheck() async throws {
        let techpack = try text("techpack.yaml")
        let listed = techpack.matches(of: /command: (mcs\/checks\/[\w.-]+\.sh)/).map { String($0.1) }
        let checks = Doctor.checks.filter { !Self.coveredByMCS.contains($0.id) }
        #expect(listed.count == checks.count)
        for check in Doctor.checks where Self.coveredByMCS.contains(check.id) {
            let wrapper = "mcs/checks/\(check.id.replacingOccurrences(of: "/", with: "--")).sh"
            #expect(!listed.contains(wrapper), "\(check.id): mcs does this itself, so the techpack leaves it out")
            #expect(!FileManager.default.fileExists(atPath: Self.repository.appending(path: wrapper).path), "\(wrapper)")
        }
        for check in checks {
            let wrapper = "mcs/checks/\(check.id.replacingOccurrences(of: "/", with: "--")).sh"
            #expect(listed.contains(wrapper), "\(check.id) missing from techpack.yaml")
            #expect(FileManager.default.isExecutableFile(atPath: Self.repository.appending(path: wrapper).path), "\(wrapper)")
            #expect(try text(wrapper).contains("doctor --check \(check.id)\n"), "\(wrapper)")
        }
    }

    /// mcs asks only for the workspace; the simulator defaults to the newest iPhone, `xcrew setup` finds
    /// the unit-test scheme, and `/xcrew:setup` finds the others instead of having them typed in.
    @Test func techpackAsksOnlyForTheWorkspace() async throws {
        let keys = try text("techpack.yaml").matches(of: /- key: (\w+)/).map { String($0.1) }
        #expect(keys == ["PROJECT"])
        #expect(Set(keys).isSubset(of: Set(SetupCommand.mcsKeys.values)), "a prompt no setup option reads")
    }

    /// mcs offers the workspaces and projects it finds; xcrew must recognise the same ones.
    @Test func techpackDetectsTheContainersXcrewDoes() throws {
        let patterns = try text("techpack.yaml").matches(of: /^\s+- "(\*\.xc\w+)"$/.anchorsMatchLineEndings()).map { String($0.1) }
        #expect(patterns == Project.containerExtensions.map { "*\($0)" })
    }

    @Test func techpackConfiguresThroughTheCLI() async throws {
        let techpack = try text("techpack.yaml")
        #expect(techpack.contains("script: mcs/configure.sh"))
        #expect(try text("mcs/configure.sh").contains("bin/xcrew\" setup"))
        #expect(techpack.contains("brew: getsentry/xcodebuildmcp/mobilebuildmcp"))
    }

    // MARK: Plugin identity

    @Test func marketplaceVersionIsOneEverywhere() throws {
        let version = XcrewVersion.current
        #expect(try json(".claude-plugin/plugin.json")["version"] as? String == version)
        #expect(try text("CHANGELOG.md").contains("\n## \(version)"))
    }

    /// The shim states the first build's time; the measurements behind it are in docs/findings.md, *Toolchains*.
    @Test func listingAgreesWithTheShimOnTheFirstBuildTime() throws {
        let range = try #require(try text("bin/xcrew").firstMatch(of: /building the CLI for this version \(once, (.+) s\)/)?.1)
        #expect(try text("README.md").contains("builds Xcrew's small Swift CLI, \(range) seconds, once per version"))
    }

    /// mcs loads the plugin in place from the pack's checkout, at the root, and refuses it unless plugin.json names it
    /// as `pluginAndMarketplaceAgree` requires.
    @Test func techpackLoadsThePluginFromThePack() throws {
        #expect(try text("techpack.yaml").contains("plugin: \"xcrew@pack\"\n"))
    }

    /// mcs reads a change under an `ignore:` entry as noise and never says an update is out for it.
    @Test func techpackNoticesEveryChangeToWhatThePluginRuns() throws {
        let ignored = try text("techpack.yaml").firstMatch(of: /\nignore:\n((?:\s+(?:-|#).*\n)+)/).map { String($0.1) } ?? ""
        let entries = ignored.matches(of: /- (\S+)/).map { String($0.1) }
        #expect(!entries.isEmpty)
        let manifests = try [".claude-plugin/plugin.json", "hooks/hooks.json"].map(text).joined()
        let launched = manifests.matches(of: /\$\{CLAUDE_PLUGIN_ROOT\}\/([\w.-]+\/)/).map { String($0.1) }
        let types = try #require((try json(".claude-plugin/plugin.json")["types"] as? String)?.split(separator: "/").dropFirst().first)
        let packScripts = try text("techpack.yaml").matches(of: /(?:script|command): ([\w.-]+\/)/).map { String($0.1) }
        // Claude Code's plugin layout, and what bin/xcrew builds from.
        let fixed = [".claude-plugin/", "hooks/", "skills/", "Package.swift", "Sources/", "context/"]
        let runs = Set(fixed + launched + packScripts + ["\(types)/"])
        #expect(runs.isSuperset(of: ["bin/", "libexec/", "types/", "mcs/"]))
        for path in runs {
            #expect(!entries.contains { path.hasPrefix($0) || $0.hasPrefix(path) }, "\(path)")
        }
    }

    /// The branch the marketplace installs, which releases move.
    func installedBranch() throws -> String {
        let plugins = try #require(try json(".claude-plugin/marketplace.json")["plugins"] as? [[String: Any]])
        return try #require((plugins.first?["source"] as? [String: String])?["ref"])
    }

    /// An mcs install runs the pack's checkout, so it follows the branch the marketplace installs only when added at it.
    @Test func techpackInstallsFollowTheBranchTheMarketplaceDoes() throws {
        let branch = try installedBranch()
        #expect(try text("README.md").contains("mcs pack add breferrari/xcrew --ref \(branch) && mcs sync"))
    }

    @Test func marketplaceAndPluginAgree() async throws {
        #expect(try json(".claude-plugin/plugin.json")["name"] as? String == "xcrew")
        let plugins = try #require(try json(".claude-plugin/marketplace.json")["plugins"] as? [[String: Any]])
        #expect(plugins.map { $0["name"] as? String } == ["xcrew"])
    }

    /// Installs follow `stable`, which only the release workflow moves, to a tag it accepted: a relative source would
    /// install main's HEAD under the last release's version.
    @Test func marketplaceInstallsTheStableBranch() throws {
        let repository = try #require((try json(".claude-plugin/plugin.json")["repository"] as? String)?.replacing("https://github.com/", with: ""))
        let plugins = try #require(try json(".claude-plugin/marketplace.json")["plugins"] as? [[String: Any]])
        let source = plugins.first?["source"] as? [String: String]
        #expect(source == ["source": "github", "repo": repository, "ref": "stable"])
        #expect(XcrewUpdateCheck.latestRelease == "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// The release workflow moves `stable` only after every check on the tag passed, and before it publishes, so
    /// `xcrew doctor` never names a release installs can't reach. GitHub makes the move only as a fast-forward, and
    /// write access is granted to that job alone; a rerun gets past both steps.
    @Test func onlyAnAcceptedReleaseMovesStable() throws {
        let release = try text(".github/workflows/release.yml")
        #expect(!release.contains("\npermissions:"), "permissions belong to the job, not the workflow")
        #expect(release.contains(#/\n    permissions:\n(?:      \S.*\n)*      contents: write\n/#))
        let steps = release.components(separatedBy: "\n      - ")
        let move = try #require(steps.firstIndex { $0.contains("refs/heads/stable") })
        #expect(steps[move].contains(#"gh api -X PATCH "repos/$GITHUB_REPOSITORY/git/refs/heads/stable" -f sha="$GITHUB_SHA" -F force=false"#))
        #expect(steps[..<move].contains { $0.contains("is what its pull request tested") })
        let publish = try #require(steps.firstIndex { $0.contains("gh release create") })
        #expect(publish > move)
        #expect(steps[publish].contains(#"gh release view "$GITHUB_REF_NAME""#))
        for forced in ["force=true", "--force", #""+"#, "continue-on-error"] { #expect(!release.contains(forced), "\(forced)") }
    }

    /// Every place that reads or moves the branch installs follow names the one the marketplace does.
    @Test(arguments: [".github/workflows/release.yml", ".github/workflows/canary.yml", "scripts/release.sh"])
    func marketplaceBranchIsNamedWhereverItMoves(_ file: String) throws {
        let branch = try installedBranch()
        let text = try text(file)
        #expect(text.contains("refs/heads/\(branch)") || text.contains("...\(branch)"), "\(file)")
    }
}

/// The mod's boundary (docs/architecture.md, *The mod's boundary*): it hooks, draws, keeps state
/// and times calls, and hands everything it reads to the Swift CLI. These fail when logic drifts
/// back into TypeScript.
@Suite struct ModBoundaryTests {
    /// The mod's own sources: tests and their fixtures and helpers aren't the mod.
    static func sources() throws -> [(name: String, text: String)] {
        let folder = ManifestTests.repository.appending(path: "hooks/mod")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
            .filter { $0.hasSuffix(".ts") && !$0.hasSuffix(".test.ts") && !["fixtures.ts", "testing.ts"].contains($0) }
            .map { ($0, try String(contentsOf: folder.appending(path: $0), encoding: .utf8)) }
    }

    /// Files using `pattern` other than those allowed it.
    static func offenders(_ pattern: some RegexComponent, allowed: Set<String>) throws -> [String] {
        try sources().filter { !allowed.contains($0.name) && $0.text.contains(pattern) }.map(\.name)
    }

    /// The plugin directory reads `$` only in the hooks module: it may go, whole, to a function declared at the top
    /// of the same file, never to a function another file exports. See docs/architecture.md.
    @Test func onlyTheHooksModuleUsesTheModsAPI() throws {
        #expect(try Self.offenders(/\$\.[a-z]+|EngineInterface|[(,]\s*\$\s*[,)]/, allowed: ["register.ts"]) == [])
    }

    /// Every hook is registered in the hooks module, one `on(` call to a line, so the directory finds each.
    @Test func onlyTheHooksModuleRegistersHooks() throws {
        #expect(try Self.offenders(/(?:^|[^\w.$])on\(['"`]|: On\b/, allowed: ["register.ts"]) == [])
        let register = try #require(try Self.sources().first { $0.name == "register.ts" }).text
        let registrations = register.split(separator: "\n").filter { $0.contains(/(?:^|[^\w.$])on\(['"`]/) }
        #expect(!registrations.isEmpty)
        #expect(registrations.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("on(") })
    }

    /// `$` goes only to the helpers `register.ts` declares at its top level, and to `claude-code`'s `read` and `update`.
    @Test func theHooksModulePassesTheModsAPIOnlyToItsOwnTopLevelFunctions() throws {
        let register = try #require(try Self.sources().first { $0.name == "register.ts" }).text
        let topLevel = Set(register.matches(of: /(?m)^(?:export )?(?:async )?function (\w+)\(/).map { String($0.1) })
        // `$` in any argument position, to a function or to a method.
        let given = Set(register.matches(of: /(?:^|[^\w$])(\w+)\((?:[^()]*?,\s*)?\$\s*[,)]/).map { String($0.1) })
        #expect(given.subtracting(topLevel).subtracting(["read", "update"]).isEmpty, "$ passed to \(given.subtracting(topLevel).subtracting(["read", "update"]).sorted())")
        #expect(!register.contains(/\.\w+\((?:[^()]*?,\s*)?\$\s*[,)]/), "$ passed to a method")
    }

    /// Reading named fields of a server's JSON answer is fine where the mod keeps what it learns; parsing text isn't.
    @Test func onlyTheCLIWrapperAndContextReadJSON() throws {
        #expect(try Self.offenders(/JSON\.parse\(/, allowed: ["cli.ts", "context.ts"]) == [])
    }

    /// The directory resolves a name without regard to scope: a helper that takes `$` named like a variable in a hook
    /// reads as `$` passed to that hook's own binding.
    @Test func eachHelperThatTakesTheModsAPIHasAUniqueName() throws {
        let register = try #require(try Self.sources().first { $0.name == "register.ts" }).text
        let helpers = register.matches(of: /(?m)^(?:export )?(?:async )?function (\w+)\(\$|^(?:export )?const (\w+) = (?:async )?\(\$/).map { String($0.1 ?? $0.2 ?? "") }
        #expect(!helpers.isEmpty)
        for helper in helpers {
            // Declarations, parameters and arrow parameters; a regular expression can't see every rebinding, so this
            // guards against the common ones.
            let bindings = register.matches(of: try Regex("\\b(?:const|let|var|function|class)\\s+\(helper)\\b|[(,]\\s*\(helper)\\s*[:)=]|\\b\(helper)\\s*=>")).count
            #expect(bindings == 1, "\(helper) is bound \(bindings) times in register.ts")
        }
    }

    /// One call site starts a process, `start` in the hooks module, and it runs only the shim or the build the shim names;
    /// `cli.ts` decides which and reads what comes back.
    @Test func theModStartsOnlyTheCLIFromOnePlace() throws {
        let register = try #require(try Self.sources().first { $0.name == "register.ts" }).text
        #expect(try Self.sources().map(\.text).joined().matches(of: /\$\.process\.run\(/).count == 1)
        let start = try #require(register.firstMatch(of: /(?ms)^function start\(.*?^}/)).output
        #expect(start.contains("$.process.run("))
        let programs = Set(register.matches(of: /start\(\$, ([^,]+),/).map { String($0.1) })
        #expect(programs == ["shimPath($.plugin.root)", "binary"])
        #expect(register.contains("const binary = await build("))
    }

    @Test func onlyToolNamesAreMatchedByPattern() throws {
        #expect(try Self.offenders(/\.exec\(|\.test\(|\.match\(|\.matchAll\(|new RegExp|\.replace\(\//, allowed: ["tools.ts"]) == [])
    }

    @Test func theModTouchesNoFiles() throws {
        #expect(try Self.offenders(/\$\.fs\./, allowed: []) == [])
    }
}
