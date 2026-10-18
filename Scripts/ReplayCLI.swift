import Foundation
import FormCoachCore
import Darwin

private actor ReplayTrace {
    var values: [ReplaySnapshot] = []
    func append(_ value: ReplaySnapshot) { values.append(value) }
}

@main
struct ReplayCLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3, let expected = Int(args[2]) else {
            print("Usage: Scripts/replay-video.sh <video-or-pose-json> <expected-count> [result.json] [minimum-descent-ms]"); exit(2)
        }
        do {
            let trace = ReplayTrace()
            let minimum = args.count > 4 ? Int(args[4]) : nil
            let summary = try await VideoReplayAnalyzer.run(url: URL(fileURLWithPath: args[1]), target: SquatTrainingTarget(minimumDescentMs: minimum)) { await trace.append($0) }
            let values = await trace.values
            let report: [String: Any] = [
                "file": URL(fileURLWithPath: args[1]).lastPathComponent,
                "expected": expected, "actual": summary.reps.count,
                "firstStandingMs": values.first(where: \.baselineReady)?.timeMs as Any? ?? NSNull(),
                "reps": summary.reps.map { ["id": $0.id, "startMs": $0.startMs, "endMs": $0.endMs] },
                "snapshots": values.map { ["timeMs": $0.timeMs, "count": $0.count, "message": $0.message, "baselineReady": $0.baselineReady] as [String: Any] }
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            var fullReport = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            fullReport["summary"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary))
            let fullData = try JSONSerialization.data(withJSONObject: fullReport, options: [.prettyPrinted, .sortedKeys])
            if args.count >= 4 { try fullData.write(to: URL(fileURLWithPath: args[3])) }
            print("\(summary.reps.count == expected ? "PASS" : "FAIL") \(args[1]): \(summary.reps.count)/\(expected), standing=\(values.first(where: \.baselineReady)?.timeMs.description ?? "none")ms")
            if summary.reps.count != expected { exit(1) }
        } catch { print("ERROR: \(error.localizedDescription)"); exit(2) }
    }
}
