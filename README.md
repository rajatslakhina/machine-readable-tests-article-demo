# TestTriage

**A triage layer over Swift Testing's machine-readable surface.** This repo is the companion demo for the article *"Your Test Suite's Primary Reader Is Now an Agent"* — Article: (added after publish).

Swift Testing now speaks two machine-facing dialects: the **ABI event stream** (`--event-stream-output-path`, a JSON Lines feed of every test record and event) and **ST-0025 tag-based execution filtering** (`swift test --skip tag:uiTest`). `TestTriage` closes the loop between them: it decodes the stream, reconstructs per-test verdicts, and emits the *next command* — the exact `swift test` invocation that re-runs only what failed.

```
event stream (JSON Lines)          verdicts                    next command
──────────────────────────  ──▶  ─────────────────────  ──▶  ─────────────────────────────
EventStreamDecoder                RunReconstructor             RerunPlanner
tolerant, per-line decode         failed / crashSuspect /      swift test --filter tag:network
skips unknown record kinds        skipped / known-issue        (or per-test id: filters)
```

## What it demonstrates

- **`EventStreamDecoder`** — tolerant JSON Lines decoding of the ABI stream. Unknown *record* kinds are skipped per the schema's own rule; unknown *event* kinds decode as `.unknown(raw)` instead of failing; malformed lines are counted, never fatal.
- **`RunReconstructor`** — folds records into per-test verdicts. The interesting one: **`crashSuspect`** — a test that emitted `testStarted` but no `testEnded` before the stream stopped. That's the crash signature: a crashed test's stream just goes silent.
- **`RerunPlanner`** — when one tag from the stream's test records covers the failing set *exactly*, it emits a single ST-0025 command (`swift test --filter tag:network`); otherwise it falls back to per-test `id:` filters with regex-escaped test IDs. Raw-identifier tags with spaces get proper single-quoting.
- **`TriageDashboardView`** — a SwiftUI dashboard over a bundled sample stream: verdict badges, tag chips, the agent's next command, and decoder health.

The package's own tests dogfood the thesis: they're written in Swift Testing with `.tags(.decoder)`, `.tags(.triage)`, `.tags(.planner)`.

## The core idea in three lines

```swift
let decoded = EventStreamDecoder().decode(streamText: streamText)
let run = RunReconstructor().reconstruct(from: decoded)
let plan = RerunPlanner().plan(for: run)   // → "swift test --filter tag:network"
```

## How to run it

1. Clone this repo.
2. Open `Demo.xcodeproj` in Xcode (the app consumes the library via a local package reference — one clone, no second repo).
3. Select the `Demo` scheme and any iOS 17+ Simulator.
4. Build & Run. No other setup.

Library only: `swift build` and `swift test` from the repo root.

## Verification status

- `swift build` and `swift test` (22 tests, including malformed-line, unknown-kind, and quoting edge cases): **passing** on Swift 6.0.3 / Linux at commit time.
- `Demo.xcodeproj` was hand-authored and structurally verified (balanced braces/parens, no dangling object references, shared scheme committed).
- **A live Simulator run was NOT performed for this commit.** This repo was produced by an unattended scheduled run, and desktop-automation access to Xcode/Simulator could not be granted without a user present to approve it. There are therefore no app screenshots in this repo yet — rather than ship a staged image, the SwiftUI layer was instead hand-reviewed against iOS 17 API availability. If you run it and something is off, an issue is very welcome.

## Sources

- [ABI JSON schema — swift-testing `Documentation/ABI/JSON.md`](https://github.com/swiftlang/swift-testing/blob/main/Documentation/ABI/JSON.md)
- [ST-0025: Tag-based test execution filtering](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0025-tag-based-test-execution-filtering.md)
- [What's new in Swift: July 2026](https://www.swift.org/blog/whats-new-in-swift-july-2026/)

## License

MIT
