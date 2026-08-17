import Foundation

/// Turns a triaged run into the *next command* — the concrete `swift test`
/// invocation that re-runs exactly what needs re-running.
///
/// This is where ST-0025 becomes load-bearing: when a tag from the stream's
/// test records covers exactly the failing set, the planner emits one
/// `--filter tag:<name>` instead of N per-test id filters. Tag taxonomy design
/// directly changes how short — and how cheap — the re-run command gets.
public struct RerunPlanner: Sendable {
    /// A planned invocation plus how it was derived, so a consumer (human or
    /// agent) can audit the plan instead of trusting it.
    public struct Plan: Equatable, Sendable, Codable {
        public enum Strategy: String, Equatable, Sendable, Codable {
            /// One `--filter tag:<name>` covered the failing set exactly.
            case tagFilter
            /// Fell back to one `--filter 'id:...'` per failing test.
            case perTestIDFilters
            /// Nothing failed; no re-run needed.
            case nothingToRerun
        }

        public var strategy: Strategy
        public var command: String?
        /// IDs of the tests the plan intends to re-run.
        public var coveredTestIDs: [String]

        public init(strategy: Strategy, command: String? = nil, coveredTestIDs: [String] = []) {
            self.strategy = strategy
            self.command = command
            self.coveredTestIDs = coveredTestIDs
        }
    }

    public init() {}

    /// Builds the minimal re-run plan for a triaged run.
    ///
    /// Selection rule, deterministic on purpose: a tag qualifies only if the
    /// set of tests carrying it (per the run's test records) is exactly the
    /// failing set — no more, no less. Ties break alphabetically. Anything
    /// looser silently re-runs passing tests or, worse, misses failing ones.
    public func plan(for run: TestRun) -> Plan {
        let failing = run.failingResults
        guard !failing.isEmpty else {
            return Plan(strategy: .nothingToRerun)
        }

        let failingIDs = Set(failing.map(\.id))

        // Membership per tag across *all* tests in the run, not just failing
        // ones — a tag that also covers passing tests must not qualify.
        var membership: [String: Set<String>] = [:]
        for result in run.results {
            for tag in result.meta.tags ?? [] {
                membership[tag, default: []].insert(result.id)
            }
        }

        let exactCover = membership
            .filter { $0.value == failingIDs }
            .keys
            .sorted()
            .first

        if let tag = exactCover {
            return Plan(
                strategy: .tagFilter,
                command: "swift test --filter \(Self.shellQuoted("tag:\(tag)"))",
                coveredTestIDs: failingIDs.sorted()
            )
        }

        let filters = failingIDs.sorted().map { id in
            "--filter \(Self.shellQuoted("id:\(Self.regexEscaped(id))"))"
        }
        return Plan(
            strategy: .perTestIDFilters,
            command: "swift test \(filters.joined(separator: " "))",
            coveredTestIDs: failingIDs.sorted()
        )
    }

    /// The quarantine command for a tag: run everything except it.
    /// Multiple `--skip` options OR together per ST-0025, so callers can
    /// chain these strings safely.
    public func quarantineCommand(skippingTag tag: String) -> String {
        "swift test --skip \(Self.shellQuoted("tag:\(tag)"))"
    }

    // MARK: - Escaping

    /// Single-quotes an argument when it needs it. ST-0025 tags are plain
    /// strings that may contain spaces (raw identifiers) — and, per the
    /// proposal, never backticks.
    static func shellQuoted(_ argument: String) -> String {
        let safe = argument.allSatisfy { character in
            character.isLetter || character.isNumber || "-_.:/^$".contains(character)
        }
        if safe && !argument.isEmpty {
            return argument
        }
        // POSIX single-quote escaping: close, insert escaped quote, reopen.
        let escaped = argument.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Escapes a test ID for use inside the `id:` regex filter, so ids with
    /// regex metacharacters (parentheses in `myTest()`, dots in module names)
    /// match literally. Hand-rolled rather than `NSRegularExpression`'s
    /// escaper because corelibs-foundation escapes a different character set
    /// on Linux — command output must be identical on every platform.
    static func regexEscaped(_ id: String) -> String {
        var escaped = String()
        escaped.reserveCapacity(id.count)
        for character in id {
            if #"\.+*?()[]{}|^$"#.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
