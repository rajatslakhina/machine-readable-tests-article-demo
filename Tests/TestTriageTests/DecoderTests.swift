import Foundation
import Testing
@testable import TestTriage

extension Tag {
    @Tag static var decoder: Self
    @Tag static var triage: Self
    @Tag static var planner: Self
}

@Suite("Event stream decoding", .tags(.decoder))
struct DecoderTests {
    @Test("Sample stream decodes with the expected record mix")
    func sampleStreamDecodes() {
        let result = EventStreamDecoder().decode(streamText: SampleRun.eventStreamJSONL)

        // 7 test records (1 suite + 6 functions) + 14 events; the
        // "telemetrySnapshot" line is ignored per the schema rule.
        #expect(result.records.count == 21)
        #expect(result.malformedLineCount == 0)
        #expect(result.ignoredRecordKinds == ["telemetrySnapshot"])
    }

    @Test("Tags ride on test records, not events")
    func tagsComeFromTestRecords() {
        let result = EventStreamDecoder().decode(streamText: SampleRun.eventStreamJSONL)

        let taggedFunctions = result.records.compactMap { record -> TestMeta? in
            if case .test(_, let meta) = record, meta.kind == .function { return meta }
            return nil
        }
        let ledger = taggedFunctions.first { $0.id == "PaymentsTests/testLedgerReplay()" }
        #expect(ledger?.tags?.sorted() == ["flaky", "network", "payments"])
    }

    @Test("Empty stream is a valid, empty result")
    func emptyStream() {
        let result = EventStreamDecoder().decode(streamText: "")
        #expect(result.records.isEmpty)
        #expect(result.malformedLineCount == 0)
        #expect(result.ignoredRecordKinds.isEmpty)
    }

    @Test("Malformed lines are counted and skipped, not fatal")
    func malformedLines() {
        let text = """
        not json at all
        {"version":0,"kind":"event","payload":{"kind":"runStarted","messages":[]}}
        {"broken": true
        [1,2,3]
        """
        let result = EventStreamDecoder().decode(streamText: text)
        #expect(result.records.count == 1)
        #expect(result.malformedLineCount == 3)
    }

    @Test("Unknown event kinds decode as .unknown instead of failing")
    func unknownEventKind() {
        let text = """
        {"version":0,"kind":"event","payload":{"kind":"quantumFluctuationObserved","messages":[],"testID":"T/x()"}}
        """
        let result = EventStreamDecoder().decode(streamText: text)
        guard case .event(_, let event)? = result.records.first else {
            Issue.record("Expected one event record")
            return
        }
        #expect(event.kind == .unknown("quantumFluctuationObserved"))
        #expect(event.kind.rawKind == "quantumFluctuationObserved")
    }

    @Test("Version field accepts both 0 and semver strings")
    func versionShapes() {
        let text = """
        {"version":0,"kind":"event","payload":{"kind":"runStarted","messages":[]}}
        {"version":"6.4","kind":"event","payload":{"kind":"runEnded","messages":[]}}
        """
        let result = EventStreamDecoder().decode(streamText: text)
        #expect(result.records.count == 2)
        guard case .event(let first, _)? = result.records.first,
              case .event(let second, _)? = result.records.last else {
            Issue.record("Expected two event records")
            return
        }
        #expect(first == .v0)
        #expect(second == .semver("6.4"))
    }
}
