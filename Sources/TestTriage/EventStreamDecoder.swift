import Foundation

/// Decodes swift-testing's ABI event stream (the JSON Lines file produced by
/// `--event-stream-output-path`) into typed records.
///
/// Two tolerance rules are load-bearing and both come straight from the schema
/// document (`Documentation/ABI/JSON.md`):
///
/// 1. "If a decoder encounters a record whose `kind` field is unrecognized,
///    the decoder should ignore that line." Unknown *record* kinds are skipped
///    and counted, never fatal.
/// 2. Event kinds are open-ended ("additional event kinds may be added in the
///    future"), so unknown *event* kinds decode as `.unknown(raw)` and flow
///    through — a triage layer that hard-fails on a new toolchain is useless
///    exactly when you need it.
///
/// Malformed lines (not valid JSON, or JSON that is not an object) are also
/// counted and skipped: one corrupt line must never take down triage of the
/// other ten thousand.
public struct EventStreamDecoder: Sendable {
    /// The result of decoding a stream: the records that decoded, plus an
    /// honest account of what did not.
    public struct DecodeResult: Sendable {
        public var records: [StreamRecord]
        /// Count of lines that were not valid JSON objects.
        public var malformedLineCount: Int
        /// Raw `kind` values of records that were skipped per the schema rule.
        public var ignoredRecordKinds: [String]

        public init(records: [StreamRecord] = [], malformedLineCount: Int = 0, ignoredRecordKinds: [String] = []) {
            self.records = records
            self.malformedLineCount = malformedLineCount
            self.ignoredRecordKinds = ignoredRecordKinds
        }
    }

    public init() {}

    /// Decodes a complete JSON Lines stream held in memory.
    public func decode(streamText: String) -> DecodeResult {
        var result = DecodeResult()
        // Split on newlines per the JSON Lines framing. `omittingEmptySubsequences`
        // makes trailing newlines and blank lines harmless.
        let lines = streamText.split(separator: "\n", omittingEmptySubsequences: true)
        result.records.reserveCapacity(lines.count)

        for line in lines {
            decode(line: String(line), into: &result)
        }
        return result
    }

    /// Decodes a single line into the running result.
    private func decode(line: String, into result: inout DecodeResult) {
        guard let data = line.data(using: .utf8) else {
            result.malformedLineCount += 1
            return
        }
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                result.malformedLineCount += 1
                return
            }
            object = parsed
        } catch {
            result.malformedLineCount += 1
            return
        }

        guard let kind = object["kind"] as? String else {
            result.malformedLineCount += 1
            return
        }

        let version = decodeVersion(object["version"])

        switch kind {
        case "test":
            guard
                let payload = object["payload"] as? [String: Any],
                let meta = decodeTestMeta(payload)
            else {
                result.malformedLineCount += 1
                return
            }
            result.records.append(.test(version: version, payload: meta))
        case "event":
            guard let payload = object["payload"] as? [String: Any] else {
                result.malformedLineCount += 1
                return
            }
            result.records.append(.event(version: version, payload: decodeEvent(payload)))
        default:
            // Schema rule: unrecognized record kinds are ignored, not errors.
            result.ignoredRecordKinds.append(kind)
        }
    }

    // MARK: - Field decoding

    private func decodeVersion(_ raw: Any?) -> SchemaVersion {
        if let number = raw as? Int {
            return number == 0 ? .v0 : .semver(String(number))
        }
        if let string = raw as? String {
            return .semver(string)
        }
        return .v0
    }

    private func decodeTestMeta(_ payload: [String: Any]) -> TestMeta? {
        guard
            let kindRaw = payload["kind"] as? String,
            let kind = TestMeta.Kind(rawValue: kindRaw),
            let name = payload["name"] as? String,
            let id = payload["id"] as? String
        else {
            return nil
        }
        return TestMeta(
            kind: kind,
            name: name,
            displayName: payload["displayName"] as? String,
            id: id,
            isParameterized: payload["isParameterized"] as? Bool,
            tags: payload["tags"] as? [String],
            sourceLocation: decodeSourceLocation(payload["sourceLocation"])
        )
    }

    private func decodeEvent(_ payload: [String: Any]) -> StreamEvent {
        let kindRaw = payload["kind"] as? String ?? ""
        var issue: IssueInfo?
        if let issueObject = payload["issue"] as? [String: Any] {
            issue = IssueInfo(
                isKnown: issueObject["isKnown"] as? Bool ?? false,
                severity: issueObject["severity"] as? String,
                isFailure: issueObject["isFailure"] as? Bool,
                sourceLocation: decodeSourceLocation(issueObject["sourceLocation"])
            )
        }

        var messages: [EventMessage] = []
        if let rawMessages = payload["messages"] as? [[String: Any]] {
            messages = rawMessages.map {
                EventMessage(symbol: $0["symbol"] as? String, text: $0["text"] as? String)
            }
        }

        var instant: Instant?
        if let rawInstant = payload["instant"] as? [String: Any] {
            instant = Instant(
                absolute: doubleValue(rawInstant["absolute"]),
                since1970: doubleValue(rawInstant["since1970"])
            )
        }

        return StreamEvent(
            kind: EventKind(rawKind: kindRaw),
            instant: instant,
            testID: payload["testID"] as? String,
            issue: issue,
            messages: messages,
            iteration: payload["iteration"] as? Int
        )
    }

    private func decodeSourceLocation(_ raw: Any?) -> SourceLocation? {
        guard let object = raw as? [String: Any] else { return nil }
        return SourceLocation(
            fileID: object["fileID"] as? String,
            filePath: object["filePath"] as? String,
            line: object["line"] as? Int,
            column: object["column"] as? Int
        )
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        return nil
    }
}
