import Foundation

/// The per-test verdict a triage layer hands to whatever consumes it next —
/// a dashboard, a CI gate, or an agent deciding its next command.
public enum Verdict: String, Codable, Sendable, CaseIterable {
    case passed
    case passedWithKnownIssues
    case passedWithWarnings
    case failed
    /// The test started and the run ended without a matching `testEnded`.
    /// In practice this is the crash signature: a crashed test's stream just
    /// stops — there is no `issueRecorded` or `testEnded` for it.
    case crashSuspect
    case skipped
    case cancelled
}

/// Everything reconstructed about one test function from the stream.
public struct TestResult: Sendable, Identifiable {
    public var id: String { meta.id }
    public var meta: TestMeta
    public var verdict: Verdict
    public var issues: [IssueInfo]
    public var messages: [EventMessage]
    /// Wall-clock duration derived from `since1970` instants, when both ends
    /// were observed.
    public var duration: TimeInterval?

    public init(
        meta: TestMeta,
        verdict: Verdict,
        issues: [IssueInfo] = [],
        messages: [EventMessage] = [],
        duration: TimeInterval? = nil
    ) {
        self.meta = meta
        self.verdict = verdict
        self.issues = issues
        self.messages = messages
        self.duration = duration
    }
}

/// A reconstructed run: the input an agent actually wants, distilled from
/// thousands of stream lines into per-test verdicts plus decoder health.
public struct TestRun: Sendable {
    public var results: [TestResult]
    public var suites: [TestMeta]
    public var malformedLineCount: Int
    public var ignoredRecordKinds: [String]
    /// Raw kinds of events the reconstructor saw but does not model (from
    /// `.unknown` event kinds) — surfaced, not swallowed.
    public var unmodeledEventKinds: [String]

    public init(
        results: [TestResult] = [],
        suites: [TestMeta] = [],
        malformedLineCount: Int = 0,
        ignoredRecordKinds: [String] = [],
        unmodeledEventKinds: [String] = []
    ) {
        self.results = results
        self.suites = suites
        self.malformedLineCount = malformedLineCount
        self.ignoredRecordKinds = ignoredRecordKinds
        self.unmodeledEventKinds = unmodeledEventKinds
    }

    public func count(of verdict: Verdict) -> Int {
        results.reduce(into: 0) { partial, result in
            if result.verdict == verdict { partial += 1 }
        }
    }

    public var failingResults: [TestResult] {
        results.filter { $0.verdict == .failed || $0.verdict == .crashSuspect }
    }
}

/// Folds a decoded record sequence into a `TestRun`.
public struct RunReconstructor: Sendable {
    public init() {}

    public func reconstruct(from decodeResult: EventStreamDecoder.DecodeResult) -> TestRun {
        var functionMeta: [String: TestMeta] = [:]
        var suiteMeta: [TestMeta] = []
        var started: [String: Double?] = [:]
        var ended: [String: Double?] = [:]
        var skipped: Set<String> = []
        var cancelled: Set<String> = []
        var issuesByTest: [String: [IssueInfo]] = [:]
        var messagesByTest: [String: [EventMessage]] = [:]
        var unmodeledEventKinds: [String] = []

        for record in decodeResult.records {
            switch record {
            case .test(_, let meta):
                switch meta.kind {
                case .function:
                    functionMeta[meta.id] = meta
                case .suite:
                    suiteMeta.append(meta)
                }
            case .event(_, let event):
                let testID = event.testID
                switch event.kind {
                case .testStarted:
                    if let testID { started[testID] = event.instant?.since1970 }
                case .testEnded:
                    if let testID { ended[testID] = event.instant?.since1970 }
                case .testSkipped:
                    if let testID { skipped.insert(testID) }
                case .testCancelled, .testCaseCancelled:
                    if let testID { cancelled.insert(testID) }
                case .issueRecorded:
                    if let testID, let issue = event.issue {
                        issuesByTest[testID, default: []].append(issue)
                        messagesByTest[testID, default: []].append(contentsOf: event.messages)
                    }
                case .unknown(let raw):
                    unmodeledEventKinds.append(raw)
                case .runStarted, .runEnded, .testCaseStarted, .testCaseEnded, .valueAttached:
                    // Run framing and per-case detail are not needed for
                    // function-level verdicts; nothing to fold in here.
                    break
                }
            }
        }

        // A stream can contain events for tests whose metadata record was
        // missed (truncated stream). Synthesize minimal metadata so those
        // tests still show up in triage instead of vanishing.
        var allIDs = Set(functionMeta.keys)
        allIDs.formUnion(started.keys)
        allIDs.formUnion(ended.keys)
        allIDs.formUnion(skipped)
        allIDs.formUnion(cancelled)
        allIDs.formUnion(issuesByTest.keys)

        var results: [TestResult] = []
        results.reserveCapacity(allIDs.count)

        for id in allIDs.sorted() {
            let meta = functionMeta[id] ?? TestMeta(kind: .function, name: id, id: id)
            let issues = issuesByTest[id] ?? []
            let verdict = Self.verdict(
                issues: issues,
                wasStarted: started.keys.contains(id),
                wasEnded: ended.keys.contains(id),
                wasSkipped: skipped.contains(id),
                wasCancelled: cancelled.contains(id)
            )

            var duration: TimeInterval?
            if let start = started[id] ?? nil, let end = ended[id] ?? nil, end >= start {
                duration = end - start
            }

            results.append(
                TestResult(
                    meta: meta,
                    verdict: verdict,
                    issues: issues,
                    messages: messagesByTest[id] ?? [],
                    duration: duration
                )
            )
        }

        return TestRun(
            results: results,
            suites: suiteMeta,
            malformedLineCount: decodeResult.malformedLineCount,
            ignoredRecordKinds: decodeResult.ignoredRecordKinds,
            unmodeledEventKinds: unmodeledEventKinds
        )
    }

    /// The classification rules, in priority order. Kept as a pure static
    /// function so the rules are unit-testable in isolation.
    static func verdict(
        issues: [IssueInfo],
        wasStarted: Bool,
        wasEnded: Bool,
        wasSkipped: Bool,
        wasCancelled: Bool
    ) -> Verdict {
        if wasSkipped { return .skipped }
        if wasCancelled { return .cancelled }
        if issues.contains(where: { $0.countsAsFailure }) { return .failed }
        if wasStarted && !wasEnded {
            // Started, never ended, and no failing issue recorded: the
            // process most likely died mid-test.
            return .crashSuspect
        }
        if issues.contains(where: { $0.isKnown }) { return .passedWithKnownIssues }
        if !issues.isEmpty { return .passedWithWarnings }
        return .passed
    }
}
