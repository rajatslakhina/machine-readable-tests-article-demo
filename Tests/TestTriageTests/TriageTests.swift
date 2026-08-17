import Foundation
import Testing
@testable import TestTriage

@Suite("Run reconstruction and verdicts", .tags(.triage))
struct TriageTests {
    @Test("Sample run produces the expected verdict per test")
    func sampleRunVerdicts() {
        let run = SampleRun.reconstructedRun()
        #expect(run.results.count == 6)
        #expect(run.suites.count == 1)

        let verdictsByID = Dictionary(uniqueKeysWithValues: run.results.map { ($0.id, $0.verdict) })
        #expect(verdictsByID["PaymentsTests/testCardAuthorization()"] == .failed)
        #expect(verdictsByID["PaymentsTests/testRefundRoundTrip()"] == .failed)
        #expect(verdictsByID["PaymentsTests/testReceiptFormatting()"] == .skipped)
        #expect(verdictsByID["PaymentsTests/testCurrencyTable()"] == .passedWithKnownIssues)
        #expect(verdictsByID["PaymentsTests/testLegacyGatewayContract()"] == .passed)
        #expect(verdictsByID["PaymentsTests/testLedgerReplay()"] == .crashSuspect)
    }

    @Test("Started-but-never-ended is the crash signature")
    func crashSuspectRule() {
        let verdict = RunReconstructor.verdict(
            issues: [],
            wasStarted: true,
            wasEnded: false,
            wasSkipped: false,
            wasCancelled: false
        )
        #expect(verdict == .crashSuspect)
    }

    @Test("A failing issue outranks the crash heuristic")
    func failingIssueOutranksCrash() {
        let failing = IssueInfo(isKnown: false, severity: "error", isFailure: true)
        let verdict = RunReconstructor.verdict(
            issues: [failing],
            wasStarted: true,
            wasEnded: false,
            wasSkipped: false,
            wasCancelled: false
        )
        #expect(verdict == .failed)
    }

    @Test("Known issues and warnings do not fail the test")
    func nonFailingIssues() {
        let known = IssueInfo(isKnown: true, severity: "error", isFailure: false)
        #expect(
            RunReconstructor.verdict(issues: [known], wasStarted: true, wasEnded: true, wasSkipped: false, wasCancelled: false)
            == .passedWithKnownIssues
        )

        let warning = IssueInfo(isKnown: false, severity: "warning", isFailure: false)
        #expect(
            RunReconstructor.verdict(issues: [warning], wasStarted: true, wasEnded: true, wasSkipped: false, wasCancelled: false)
            == .passedWithWarnings
        )
    }

    @Test("Missing isFailure falls back to !isKnown (v0 streams)")
    func v0IssueFallback() {
        let v0Unknown = IssueInfo(isKnown: false, severity: nil, isFailure: nil)
        #expect(v0Unknown.countsAsFailure)

        let v0Known = IssueInfo(isKnown: true, severity: nil, isFailure: nil)
        #expect(!v0Known.countsAsFailure)
    }

    @Test("Events for tests with no metadata record still surface")
    func synthesizedMetadata() {
        let text = """
        {"version":0,"kind":"event","payload":{"kind":"testStarted","messages":[],"testID":"Orphan/test()"}}
        {"version":0,"kind":"event","payload":{"kind":"testEnded","messages":[],"testID":"Orphan/test()"}}
        """
        let decoded = EventStreamDecoder().decode(streamText: text)
        let run = RunReconstructor().reconstruct(from: decoded)
        #expect(run.results.count == 1)
        #expect(run.results.first?.verdict == .passed)
        #expect(run.results.first?.meta.name == "Orphan/test()")
    }

    @Test("Durations come from since1970 instants")
    func durations() {
        let run = SampleRun.reconstructedRun()
        let card = run.results.first { $0.id == "PaymentsTests/testCardAuthorization()" }
        guard let duration = card?.duration else {
            Issue.record("Expected a duration for testCardAuthorization()")
            return
        }
        #expect(abs(duration - 0.9) < 0.0001)
    }
}
