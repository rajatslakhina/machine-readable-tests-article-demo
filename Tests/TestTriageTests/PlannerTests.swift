import Foundation
import Testing
@testable import TestTriage

@Suite("Re-run planning", .tags(.planner))
struct PlannerTests {
    @Test("Sample run: the network tag covers the failing set exactly")
    func sampleRunUsesTagFilter() {
        let run = SampleRun.reconstructedRun()
        let plan = RerunPlanner().plan(for: run)

        #expect(plan.strategy == .tagFilter)
        #expect(plan.command == "swift test --filter tag:network")
        #expect(plan.coveredTestIDs == [
            "PaymentsTests/testCardAuthorization()",
            "PaymentsTests/testLedgerReplay()",
            "PaymentsTests/testRefundRoundTrip()"
        ])
    }

    @Test("A tag that also covers passing tests does not qualify")
    func supersetTagRejected() {
        // "payments" covers all six tests in the sample, including passing
        // ones — the planner must not choose it even though it covers the
        // failing set.
        let run = SampleRun.reconstructedRun()
        let plan = RerunPlanner().plan(for: run)
        #expect(plan.command?.contains("payments") == false)
    }

    @Test("No exact-cover tag falls back to per-test id filters")
    func perTestIDFallback() {
        let failedMeta = TestMeta(kind: .function, name: "testA()", id: "S/testA()", tags: ["network"])
        let crashMeta = TestMeta(kind: .function, name: "testB()", id: "S/testB()", tags: nil)
        let passMeta = TestMeta(kind: .function, name: "testC()", id: "S/testC()", tags: ["network"])
        let run = TestRun(results: [
            TestResult(meta: failedMeta, verdict: .failed),
            TestResult(meta: crashMeta, verdict: .crashSuspect),
            TestResult(meta: passMeta, verdict: .passed)
        ])

        let plan = RerunPlanner().plan(for: run)
        #expect(plan.strategy == .perTestIDFilters)
        #expect(plan.command == #"swift test --filter 'id:S/testA\(\)' --filter 'id:S/testB\(\)'"#)
    }

    @Test("All green means nothing to re-run")
    func nothingToRerun() {
        let meta = TestMeta(kind: .function, name: "testA()", id: "S/testA()")
        let run = TestRun(results: [TestResult(meta: meta, verdict: .passed)])
        let plan = RerunPlanner().plan(for: run)
        #expect(plan.strategy == .nothingToRerun)
        #expect(plan.command == nil)
    }

    @Test("Raw-identifier tags with spaces get single-quoted")
    func rawIdentifierTagQuoting() {
        let command = RerunPlanner().quarantineCommand(skippingTag: "some tag with spaces")
        #expect(command == "swift test --skip 'tag:some tag with spaces'")
    }

    @Test("Plain tags stay unquoted")
    func plainTagUnquoted() {
        let command = RerunPlanner().quarantineCommand(skippingTag: "flaky")
        #expect(command == "swift test --skip tag:flaky")
    }

    @Test("Single quotes inside a tag are POSIX-escaped")
    func embeddedQuoteEscaping() {
        let quoted = RerunPlanner.shellQuoted("tag:o'clock")
        #expect(quoted == #"'tag:o'\''clock'"#)
    }

    @Test("Test ids are regex-escaped for the id: filter")
    func regexEscaping() {
        let escaped = RerunPlanner.regexEscaped("Suite/test(x: Int)")
        #expect(escaped == #"Suite/test\(x: Int\)"#)
    }

    @Test("Empty run plans safely")
    func emptyRun() {
        let plan = RerunPlanner().plan(for: TestRun())
        #expect(plan.strategy == .nothingToRerun)
        #expect(plan.coveredTestIDs.isEmpty)
    }
}
