import Foundation

// MARK: - Schema version

/// The `version` field of an ABI record.
///
/// Per swift-testing's `Documentation/ABI/JSON.md`, the version is either the
/// integer `0` (the initial ST-0002 schema) or a semver string such as `"6.3"`
/// or `"6.4"` for later revisions. Both shapes appear in real streams, so the
/// decoder accepts both.
public enum SchemaVersion: Equatable, Sendable, Codable {
    case v0
    case semver(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            // Any integer version is treated as the v0 family; only 0 is
            // defined today, but an unknown integer should not kill decoding.
            self = number == 0 ? .v0 : .semver(String(number))
        } else {
            self = .semver(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .v0: try container.encode(0)
        case .semver(let value): try container.encode(value)
        }
    }
}

// MARK: - Shared leaf types

/// A source location as emitted by the event stream.
public struct SourceLocation: Equatable, Sendable, Codable {
    public var fileID: String?
    public var filePath: String?
    public var line: Int?
    public var column: Int?

    public init(fileID: String? = nil, filePath: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.fileID = fileID
        self.filePath = filePath
        self.line = line
        self.column = column
    }
}

/// A point in time: `absolute` is toolchain-defined, `since1970` is Unix time.
/// Durations in this library are computed from `since1970` so they are
/// comparable across records regardless of the system epoch.
public struct Instant: Equatable, Sendable, Codable {
    public var absolute: Double?
    public var since1970: Double?

    public init(absolute: Double? = nil, since1970: Double? = nil) {
        self.absolute = absolute
        self.since1970 = since1970
    }
}

/// Issue metadata attached to an `issueRecorded` event.
///
/// `severity` and `isFailure` were added by ST-0013 (schema `"6.3"`); streams
/// from older toolchains omit them, so both are optional. When `isFailure` is
/// absent, this library falls back to `!isKnown` — the v0-era interpretation,
/// where every recorded issue on a test was a failure unless it was known.
public struct IssueInfo: Equatable, Sendable, Codable {
    public var isKnown: Bool
    public var severity: String?
    public var isFailure: Bool?
    public var sourceLocation: SourceLocation?

    public init(isKnown: Bool, severity: String? = nil, isFailure: Bool? = nil, sourceLocation: SourceLocation? = nil) {
        self.isKnown = isKnown
        self.severity = severity
        self.isFailure = isFailure
        self.sourceLocation = sourceLocation
    }

    /// Whether this issue should count against the test's verdict.
    public var countsAsFailure: Bool {
        if let isFailure { return isFailure }
        return !isKnown
    }
}

/// A human-readable message attached to an event (`symbol` + `text`).
public struct EventMessage: Equatable, Sendable, Codable {
    public var symbol: String?
    public var text: String?

    public init(symbol: String? = nil, text: String? = nil) {
        self.symbol = symbol
        self.text = text
    }
}

// MARK: - Test records

/// A `"kind": "test"` record: a suite or a test function, streamed before
/// most events. Tags arrive here (ST-0019, schema `"6.4"`), which is why this
/// record — not the event — is where a triage layer learns the taxonomy.
public struct TestMeta: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case suite
        case function
    }

    public var kind: Kind
    public var name: String
    public var displayName: String?
    public var id: String
    public var isParameterized: Bool?
    public var tags: [String]?
    public var sourceLocation: SourceLocation?

    public init(
        kind: Kind,
        name: String,
        displayName: String? = nil,
        id: String,
        isParameterized: Bool? = nil,
        tags: [String]? = nil,
        sourceLocation: SourceLocation? = nil
    ) {
        self.kind = kind
        self.name = name
        self.displayName = displayName
        self.id = id
        self.isParameterized = isParameterized
        self.tags = tags
        self.sourceLocation = sourceLocation
    }
}

// MARK: - Event records

/// Event kinds defined by the ABI schema, plus `.unknown` so that event kinds
/// added by future toolchains degrade gracefully instead of failing decode.
public enum EventKind: Equatable, Sendable {
    case runStarted
    case testStarted
    case testCaseStarted
    case issueRecorded
    case testCaseEnded
    case testEnded
    case testSkipped
    case runEnded
    case valueAttached
    case testCancelled
    case testCaseCancelled
    case unknown(String)

    public init(rawKind: String) {
        switch rawKind {
        case "runStarted": self = .runStarted
        case "testStarted": self = .testStarted
        case "testCaseStarted": self = .testCaseStarted
        case "issueRecorded": self = .issueRecorded
        case "testCaseEnded": self = .testCaseEnded
        case "testEnded": self = .testEnded
        case "testSkipped": self = .testSkipped
        case "runEnded": self = .runEnded
        case "valueAttached": self = .valueAttached
        case "testCancelled": self = .testCancelled
        case "testCaseCancelled": self = .testCaseCancelled
        default: self = .unknown(rawKind)
        }
    }

    public var rawKind: String {
        switch self {
        case .runStarted: "runStarted"
        case .testStarted: "testStarted"
        case .testCaseStarted: "testCaseStarted"
        case .issueRecorded: "issueRecorded"
        case .testCaseEnded: "testCaseEnded"
        case .testEnded: "testEnded"
        case .testSkipped: "testSkipped"
        case .runEnded: "runEnded"
        case .valueAttached: "valueAttached"
        case .testCancelled: "testCancelled"
        case .testCaseCancelled: "testCaseCancelled"
        case .unknown(let raw): raw
        }
    }
}

/// A `"kind": "event"` record's payload.
public struct StreamEvent: Equatable, Sendable {
    public var kind: EventKind
    public var instant: Instant?
    public var testID: String?
    public var issue: IssueInfo?
    public var messages: [EventMessage]
    public var iteration: Int?

    public init(
        kind: EventKind,
        instant: Instant? = nil,
        testID: String? = nil,
        issue: IssueInfo? = nil,
        messages: [EventMessage] = [],
        iteration: Int? = nil
    ) {
        self.kind = kind
        self.instant = instant
        self.testID = testID
        self.issue = issue
        self.messages = messages
        self.iteration = iteration
    }
}

// MARK: - Top-level record

/// One decoded line of the stream.
public enum StreamRecord: Equatable, Sendable {
    case test(version: SchemaVersion, payload: TestMeta)
    case event(version: SchemaVersion, payload: StreamEvent)
}
