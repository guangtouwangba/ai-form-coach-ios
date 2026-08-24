import Foundation
import FormCoachCore

@MainActor
final class AppModel: ObservableObject {
    enum Step: Hashable { case onboarding, selection, configuration, positioning, calibration, live, summary, history, settings }
    enum LiveStatus: Equatable { case ready, active, paused(String), degraded(String) }

    @Published var step: Step = .onboarding
    @Published var trainingSide: TrainingSide = .right
    @Published var variant: ExerciseVariant = .general
    @Published var speechEnabled = true
    @Published var calibrationProgress = 0
    @Published var calibrationMessage = "保持起始姿势，然后完成 3 次轻负重动作"
    @Published var repCount = 0
    @Published var liveStatus: LiveStatus = .ready
    @Published var isAnalysisPaused = false
    @Published var latestCue: String?
    @Published var summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
    @Published var selectedRep: RepSummary?

    private let engine = WorkoutSessionEngine()
    private let speech = SpeechService()
    private var demoTask: Task<Void, Never>?
    private var calibrationCollector = GuidedCalibrationCollector()
    private var acceptsWorkoutObservations = false

    deinit { demoTask?.cancel() }

    func acknowledgeSafety() { step = .selection }
    func selectExercise() { step = .configuration }
    func confirmConfiguration() { step = .positioning }
    func beginPositioning() {
        calibrationCollector.reset()
        calibrationProgress = 0
        calibrationMessage = "保持起始姿势，然后完成 3 次轻负重动作"
        step = .calibration
    }

    func receiveCalibration(_ observation: PoseObservation) {
        guard let update = calibrationCollector.ingest(observation) else { return }
        calibrationProgress = update.completedRepCount
        if update.error != nil {
            calibrationMessage = "三次动作差异较大，请稳定节奏后重新完成 3 次"
        } else if let profile = update.profile {
            calibrationMessage = "校准完成"
            startLiveWorkout(calibration: profile)
        } else {
            calibrationMessage = "已记录第 \(update.completedRepCount) 次"
        }
    }

    func startLiveWorkout(calibration: CalibrationProfile) {
        demoTask?.cancel()
        repCount = 0
        latestCue = nil
        liveStatus = .active
        isAnalysisPaused = false
        let config = SessionConfig(trainingSide: trainingSide, variant: variant, speechEnabled: speechEnabled, saveVideo: false)
        Task {
            await engine.start(config: config, calibration: calibration)
            acceptsWorkoutObservations = true
            step = .live
        }
    }

    func receive(_ observation: PoseObservation) async {
        guard acceptsWorkoutObservations, !isAnalysisPaused else { return }
        let events = await engine.ingest(observation)
        consume(events)
    }

    func toggleAnalysisPause() {
        isAnalysisPaused.toggle()
        liveStatus = isAnalysisPaused ? .paused("manual") : .active
    }

    func startDemoWorkout() {
        demoTask?.cancel()
        step = .live
        repCount = 0
        latestCue = nil
        liveStatus = .active
        let config = SessionConfig(trainingSide: trainingSide, variant: variant, speechEnabled: speechEnabled, saveVideo: false)
        let calibration = DemoSequence.calibration
        demoTask = Task { [weak self] in
            guard let self else { return }
            await engine.start(config: config, calibration: calibration)
            for (index, observation) in DemoSequence.session.enumerated() {
                guard !Task.isCancelled else { return }
                let events = await engine.ingest(observation)
                consume(events)
                if index < DemoSequence.session.count - 1 { try? await Task.sleep(for: .milliseconds(115)) }
            }
            summary = await engine.finish()
        }
    }

    func finishWorkout() {
        demoTask?.cancel()
        acceptsWorkoutObservations = false
        Task { summary = await engine.finish(); step = .summary }
    }

    func showRep(_ rep: RepSummary) { selectedRep = rep }
    func resetWorkout() { selectedRep = nil; step = .positioning }
    func openHistory() { step = .history }
    func openSettings() { step = .settings }
    func goHome() { step = .selection }

    private func consume(_ events: [SessionEvent]) {
        for event in events {
            switch event {
            case let .repCompleted(rep):
                repCount = rep.id
            case let .feedback(feedback):
                latestCue = cue(for: feedback.issue)
                if speechEnabled { speech.speak(latestCue ?? "") }
            case let .analysisPaused(reason):
                liveStatus = .paused(reason)
            case .analysisResumed:
                liveStatus = .active
            default:
                break
            }
        }
    }

    private func cue(for issue: IssueType) -> String {
        switch issue {
        case .torsoCollapse: return String(localized: "cue.torso_stable")
        case .insufficientDepth: return String(localized: "cue.go_lower")
        case .fastDescent: return String(localized: "cue.control_descent")
        }
    }
}

private enum DemoSequence {
    static let calibration = CalibrationProfile(topHipY: 0.70, torsoLength: 0.25, targetDepth: 0.40, baselineTrunkDelta: 3, targetDescentDurationMs: 800)
    static var session: [PoseObservation] {
        makeRep(start: 0, trunkAtBottom: 11) +
        makeRep(start: 2_100, trunkAtBottom: 34) +
        makeRep(start: 4_200, trunkAtBottom: 10) +
        makeRep(start: 6_300, trunkAtBottom: 32)
    }

    private static func makeRep(start: Int, trunkAtBottom: Double) -> [PoseObservation] {
        [
            pose(start, 0.70, 8), pose(start + 250, 0.65, 9), pose(start + 500, 0.60, 10),
            pose(start + 800, 0.58, trunkAtBottom), pose(start + 950, 0.58, trunkAtBottom),
            pose(start + 1_200, 0.63, 9), pose(start + 1_500, 0.69, 8), pose(start + 1_700, 0.70, 8)
        ]
    }

    private static func pose(_ timestamp: Int, _ hipY: Double, _ lean: Double) -> PoseObservation {
        let imageHipY = 1 - hipY
        let torso = 0.25
        let dx = sin(lean * .pi / 180) * torso
        let dy = cos(lean * .pi / 180) * torso
        let shoulderY = 1 - (hipY + dy)
        func point(_ x: Double, _ y: Double) -> Landmark { Landmark(x: x, y: y, visibility: 0.99, presence: 0.99) }
        return PoseObservation(timestampMs: timestamp, landmarks: [
            .leftShoulder: point(0.48 - dx, shoulderY), .rightShoulder: point(0.52 - dx, shoulderY),
            .leftHip: point(0.48, imageHipY), .rightHip: point(0.52, imageHipY),
            .rightKnee: point(0.40, imageHipY + 0.16), .rightAnkle: point(0.34, 0.88),
            .leftKnee: point(0.68, 0.74), .leftAnkle: point(0.82, 0.68)
        ], inferenceMs: 12, engineVersion: "review-demo-1")
    }
}
