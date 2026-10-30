import Foundation

/// The processes running, from `ps -axo pid=,ppid=,etime=,command=`: who started whom, and how long ago.
struct ProcessList: Sendable {
    struct Process: Sendable, Equatable {
        let id: Int32
        let parent: Int32
        /// Seconds since it started, from `ps`'s `etime`.
        let elapsed: Int
        let command: String
        /// The file name of the program it runs, from `ps`'s `comm`: `claude` even in a folder with a space in its name.
        var program: String = ""
        /// The program's whole path, from `comm`.
        var programPath: String = ""
    }

    let processes: [Process]
    private let byID: [Int32: Process]

    /// `comm` is the program's path alone, the last field, so a space in it doesn't shift the fields before it.
    static func load(using runner: any CommandRunning) async -> ProcessList {
        async let processes = runner.run("ps", "-axo", "pid=,ppid=,etime=,command=")
        async let programs = runner.run("ps", "-axo", "pid=,comm=")
        return ProcessList(ps: await processes.stdout, comm: await programs.stdout)
    }

    /// Each process's program, by id, as its whole path: `ps -axo pid=,comm=`.
    static func programs(using runner: any CommandRunning) async -> [Int32: String] {
        programs(in: await runner.run("ps", "-axo", "pid=,comm=").stdout)
    }

    static func programs(in comm: String) -> [Int32: String] {
        comm.split(whereSeparator: \.isNewline).reduce(into: [Int32: String]()) { programs, line in
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if fields.count == 2, let id = Int32(fields[0]) { programs[id] = String(fields[1]) }
        }
    }

    init(ps: String, comm: String = "") {
        let programs = Self.programs(in: comm)
        processes = ps.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let id = Int32(fields[0]), let parent = Int32(fields[1]), let elapsed = Self.seconds(String(fields[2])) else { return nil }
            let path = programs[id] ?? ""
            return Process(id: id, parent: parent, elapsed: elapsed, command: String(fields[3]), program: String(path.split(separator: "/").last ?? ""), programPath: path)
        }
        byID = Dictionary(processes.map { ($0.id, $0) }) { first, _ in first }
    }

    static func seconds(_ etime: String) -> Int? {
        let days = etime.split(separator: "-")
        let clock = (days.last ?? "").split(separator: ":").compactMap { Int($0) }
        guard (2...3).contains(clock.count), days.count <= 2 else { return nil }
        let wholeDays = days.count == 2 ? Int(days[0]) ?? 0 : 0
        return clock.reduce(0) { $0 * 60 + $1 } + wholeDays * 86_400
    }

    /// The processes above `id`, nearest first.
    func ancestors(of id: Int32) -> [Process] {
        var chain: [Process] = []
        var seen: Set<Int32> = []
        var current = byID[id]?.parent
        while let next = current, seen.insert(next).inserted, let process = byID[next] {
            chain.append(process)
            current = process.parent
        }
        return chain
    }
}
