import Foundation

/// A bundled sample stream so the demo app can show real triage output with
/// zero file plumbing. The shape follows swift-testing's ABI JSON schema:
/// JSON Lines, `test` records before events, tags on test records (the
/// ST-0019 / schema-"6.4" shape), and one record with an unrecognized kind
/// that a conforming decoder must ignore.
///
/// The story the fixture tells: a payments suite where two network-tagged
/// tests fail, one flaky-tagged test crashes the process, one test is
/// skipped, and one passes with a known issue.
public enum SampleRun {
    public static let eventStreamJSONL = """
    {"version":0,"kind":"test","payload":{"kind":"suite","name":"PaymentsTests","id":"PaymentsTests","sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":10,"column":1}}}
    {"version":"6.4","kind":"test","payload":{"kind":"function","name":"testCardAuthorization()","id":"PaymentsTests/testCardAuthorization()","isParameterized":false,"tags":["network","payments"],"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":18,"column":3}}}
    {"version":"6.4","kind":"test","payload":{"kind":"function","name":"testRefundRoundTrip()","id":"PaymentsTests/testRefundRoundTrip()","isParameterized":false,"tags":["network","payments"],"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":42,"column":3}}}
    {"version":"6.4","kind":"test","payload":{"kind":"function","name":"testReceiptFormatting()","id":"PaymentsTests/testReceiptFormatting()","isParameterized":false,"tags":["payments"],"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":66,"column":3}}}
    {"version":"6.4","kind":"test","payload":{"kind":"function","name":"testLedgerReplay()","id":"PaymentsTests/testLedgerReplay()","isParameterized":false,"tags":["flaky","network","payments"],"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":90,"column":3}}}
    {"version":"6.4","kind":"test","payload":{"kind":"function","name":"testCurrencyTable()","id":"PaymentsTests/testCurrencyTable()","isParameterized":true,"tags":["payments"],"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":114,"column":3}}}
    {"version":"6.4","kind":"test","payload":{"kind":"function","name":"testLegacyGatewayContract()","id":"PaymentsTests/testLegacyGatewayContract()","isParameterized":false,"tags":["payments"],"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":140,"column":3}}}
    {"version":0,"kind":"event","payload":{"kind":"runStarted","instant":{"absolute":102.5,"since1970":1765972800.0},"messages":[{"symbol":"default","text":"Test run started."}]}}
    {"version":0,"kind":"event","payload":{"kind":"testStarted","instant":{"absolute":102.6,"since1970":1765972800.1},"messages":[],"testID":"PaymentsTests/testCardAuthorization()"}}
    {"version":"6.3","kind":"event","payload":{"kind":"issueRecorded","instant":{"absolute":103.4,"since1970":1765972800.9},"issue":{"isKnown":false,"severity":"error","isFailure":true,"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":24,"column":9}},"messages":[{"symbol":"fail","text":"Expectation failed: response.status == .authorized"}],"testID":"PaymentsTests/testCardAuthorization()"}}
    {"version":0,"kind":"event","payload":{"kind":"testEnded","instant":{"absolute":103.5,"since1970":1765972801.0},"messages":[],"testID":"PaymentsTests/testCardAuthorization()"}}
    {"version":0,"kind":"event","payload":{"kind":"testStarted","instant":{"absolute":103.6,"since1970":1765972801.1},"messages":[],"testID":"PaymentsTests/testRefundRoundTrip()"}}
    {"version":"6.3","kind":"event","payload":{"kind":"issueRecorded","instant":{"absolute":104.9,"since1970":1765972802.4},"issue":{"isKnown":false,"severity":"error","isFailure":true,"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":51,"column":9}},"messages":[{"symbol":"fail","text":"Expectation failed: refund.settledAmount == original.amount"}],"testID":"PaymentsTests/testRefundRoundTrip()"}}
    {"version":0,"kind":"event","payload":{"kind":"testEnded","instant":{"absolute":105.0,"since1970":1765972802.5},"messages":[],"testID":"PaymentsTests/testRefundRoundTrip()"}}
    {"version":0,"kind":"event","payload":{"kind":"testSkipped","instant":{"absolute":105.1,"since1970":1765972802.6},"messages":[{"symbol":"skip","text":"Skipped: requires sandbox gateway credentials."}],"testID":"PaymentsTests/testReceiptFormatting()"}}
    {"version":0,"kind":"event","payload":{"kind":"testStarted","instant":{"absolute":105.2,"since1970":1765972802.7},"messages":[],"testID":"PaymentsTests/testCurrencyTable()"}}
    {"version":"6.3","kind":"event","payload":{"kind":"issueRecorded","instant":{"absolute":105.8,"since1970":1765972803.3},"issue":{"isKnown":true,"severity":"error","isFailure":false,"sourceLocation":{"filePath":"Tests/PaymentsTests.swift","line":120,"column":9}},"messages":[{"symbol":"passWithKnownIssue","text":"Known issue: HUF rounding pending upstream fix."}],"testID":"PaymentsTests/testCurrencyTable()"}}
    {"version":0,"kind":"event","payload":{"kind":"testEnded","instant":{"absolute":106.0,"since1970":1765972803.5},"messages":[],"testID":"PaymentsTests/testCurrencyTable()"}}
    {"version":0,"kind":"event","payload":{"kind":"testStarted","instant":{"absolute":106.1,"since1970":1765972803.6},"messages":[],"testID":"PaymentsTests/testLegacyGatewayContract()"}}
    {"version":0,"kind":"event","payload":{"kind":"testEnded","instant":{"absolute":106.4,"since1970":1765972803.9},"messages":[],"testID":"PaymentsTests/testLegacyGatewayContract()"}}
    {"version":"7.0","kind":"telemetrySnapshot","payload":{"note":"A record kind from the future. Conforming decoders ignore this line."}}
    {"version":0,"kind":"event","payload":{"kind":"testStarted","instant":{"absolute":106.5,"since1970":1765972804.0},"messages":[],"testID":"PaymentsTests/testLedgerReplay()"}}
    """

    /// Decoded + reconstructed on demand.
    public static func reconstructedRun() -> TestRun {
        let decoded = EventStreamDecoder().decode(streamText: eventStreamJSONL)
        return RunReconstructor().reconstruct(from: decoded)
    }
}
