#if canImport(SwiftUI)
import SwiftUI

/// The demo surface: the bundled sample stream, decoded, triaged, and planned,
/// exactly as an agent-facing CI dashboard would render it.
public struct TriageDashboardView: View {
    private let run: TestRun
    private let plan: RerunPlanner.Plan
    private let quarantine: String
    @State private var filter: VerdictFilter = .all

    private enum VerdictFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case failing = "Failing"
        case passing = "Passing"
        case other = "Other"

        var id: String { rawValue }

        func admits(_ verdict: Verdict) -> Bool {
            switch self {
            case .all:
                true
            case .failing:
                verdict == .failed || verdict == .crashSuspect
            case .passing:
                verdict == .passed || verdict == .passedWithKnownIssues || verdict == .passedWithWarnings
            case .other:
                verdict == .skipped || verdict == .cancelled
            }
        }
    }

    public init() {
        let reconstructed = SampleRun.reconstructedRun()
        run = reconstructed
        plan = RerunPlanner().plan(for: reconstructed)
        quarantine = RerunPlanner().quarantineCommand(skippingTag: "flaky")
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    countsHeader
                } header: {
                    Text("Run summary")
                }

                Section {
                    commandCard(
                        title: "Agent's next command",
                        subtitle: planSubtitle,
                        command: plan.command ?? "— nothing to re-run —"
                    )
                    commandCard(
                        title: "Quarantine suggestion",
                        subtitle: "Skip the flaky-tagged test while it's investigated",
                        command: quarantine
                    )
                } header: {
                    Text("Re-run plan")
                }

                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(VerdictFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForEach(run.results.filter { filter.admits($0.verdict) }) { result in
                        resultRow(result)
                    }
                } header: {
                    Text("Tests (\(run.results.count))")
                }

                Section {
                    LabeledContent("Malformed lines", value: "\(run.malformedLineCount)")
                    LabeledContent("Ignored record kinds", value: ignoredKindsText)
                } header: {
                    Text("Decoder health")
                } footer: {
                    Text("Unknown record kinds are ignored by design — the ABI schema requires decoders to skip lines they don't recognize.")
                }
            }
            .navigationTitle("TestTriage")
        }
    }

    private var planSubtitle: String {
        switch plan.strategy {
        case .tagFilter:
            "One tag covers the failing set exactly — ST-0025 tag filtering"
        case .perTestIDFilters:
            "No exact-cover tag; falling back to per-test id: filters"
        case .nothingToRerun:
            "All green"
        }
    }

    private var ignoredKindsText: String {
        run.ignoredRecordKinds.isEmpty ? "none" : run.ignoredRecordKinds.joined(separator: ", ")
    }

    private var countsHeader: some View {
        HStack(spacing: 12) {
            countBadge("Passed", run.count(of: .passed) + run.count(of: .passedWithKnownIssues) + run.count(of: .passedWithWarnings), .green)
            countBadge("Failed", run.count(of: .failed), .red)
            countBadge("Crash?", run.count(of: .crashSuspect), .orange)
            countBadge("Skipped", run.count(of: .skipped), .gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func countBadge(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func commandCard(title: String, subtitle: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.caption.monospaced())
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func resultRow(_ result: TestResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.meta.displayName ?? result.meta.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                verdictBadge(result.verdict)
            }
            HStack(spacing: 6) {
                ForEach(result.meta.tags ?? [], id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if let duration = result.duration {
                    Text(String(format: "%.2fs", duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let firstMessage = result.messages.first, let text = firstMessage.text {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func verdictBadge(_ verdict: Verdict) -> some View {
        let (label, color): (String, Color) = switch verdict {
        case .passed: ("passed", .green)
        case .passedWithKnownIssues: ("known issue", .teal)
        case .passedWithWarnings: ("warnings", .yellow)
        case .failed: ("failed", .red)
        case .crashSuspect: ("crash suspect", .orange)
        case .skipped: ("skipped", .gray)
        case .cancelled: ("cancelled", .gray)
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

#Preview {
    TriageDashboardView()
}
#endif
