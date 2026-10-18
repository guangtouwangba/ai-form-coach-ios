import AVFoundation
import Foundation
import SwiftData
import FormCoachCore
import SwiftUI
import ImageIO

final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

@Model
final class StoredWorkoutSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var exerciseID: String
    var variant: String
    var trainingSide: String
    var repCount: Int
    var issueCount: Int
    var summaryJSON: Data
    var mediaRelativePath: String?
    var groupsJSON: Data? = nil

    init(summary: WorkoutSummary, config: SessionConfig, startedAt: Date = .now, endedAt: Date = .now, mediaRelativePath: String? = nil) throws {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exerciseID = config.exercise.rawValue
        self.variant = config.variant.rawValue
        self.trainingSide = config.exercise == .bodyweightSquat ? "both" : config.trainingSide.rawValue
        self.repCount = summary.effectiveRepCount
        self.issueCount = summary.reps.flatMap(\.issues).filter { $0.disposition != .suppressed }.count
        self.summaryJSON = try JSONEncoder().encode(summary)
        self.mediaRelativePath = mediaRelativePath
    }

    func decodedSummary() -> WorkoutSummary? { try? JSONDecoder().decode(WorkoutSummary.self, from: summaryJSON) }
}

enum SessionDeletionService {
    static func delete(_ session: StoredWorkoutSession, context: ModelContext) throws {
        if let relative = session.mediaRelativePath {
            guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let mediaURL = base.appending(path: relative)
            if FileManager.default.fileExists(atPath: mediaURL.path) { try FileManager.default.removeItem(at: mediaURL) }
        }
        context.delete(session)
        try context.save()
    }
}

@MainActor
final class SquatReplayModel: ObservableObject {
    @Published var snapshot: ReplaySnapshot?
    @Published var summary: WorkoutSummary?
    @Published var running = false
    @Published var error: String?
    @Published var sourceName = "尚未选择录像"
    @Published var player: AVPlayer?
    @Published var engineChoice = PoseEngineChoice.recommended
    @Published var descentTargetMs = 0
    @Published var evidenceTimeMs: Int?
    @Published var comparisonReports: [PoseComparisonReport] = []
    @Published var comparisonExportURL: URL?
    @Published var comparingEngine: String?
    @Published var comparisonErrors: [String: String] = [:]
    private var operation: Task<Void, Never>?
    private var localURL: URL?
    private var generation = 0

    func importFile(_ source: URL) {
        cancel(); running = true; sourceName = source.lastPathComponent
        generation += 1; let token = generation
        operation = Task {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("squat-replay-\(UUID()).\(source.pathExtension)")
            do {
                try await Task.detached(priority: .userInitiated) {
                    let values = try source.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 0) < 500_000_000 else { throw ReplayError.invalidFile }
                    try FileManager.default.copyItem(at: source, to: url)
                }.value
                guard generation == token else { try? FileManager.default.removeItem(at: url); return }
                localURL = url
                if source.pathExtension.lowercased() != "json" { player = AVPlayer(url: url) }
                start(url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                if generation == token { self.error = "读取文件失败：\(error.localizedDescription)"; running = false }
            }
        }
    }

    func sample() {
        cancel()
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("squat-replay-\(UUID()).json")
            try JSONEncoder().encode(PoseReplayFile(version: 1, frames: SquatTestSequence.frames())).write(to: url)
            localURL = url; sourceName = "内置关键点样本（合成数据，预期 3 次）"
            start(url)
        } catch { self.error = error.localizedDescription }
    }

    func repeatAnalysis() { if let localURL { start(localURL) } }

    func seekEvidence(_ timeMs: Int) {
        guard !running, let player else { return }
        player.pause()
        player.seek(to: CMTime(value: Int64(timeMs), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        evidenceTimeMs = timeMs
    }

    func compareEngines() {
        guard let localURL, localURL.pathExtension.lowercased() != "json", !running else { return }
        operation?.cancel(); generation += 1; let token = generation
        comparisonReports = []; comparisonErrors = [:]; comparisonExportURL = nil; error = nil; running = true; snapshot = nil; summary = nil
        let target = SquatTrainingTarget(minimumDescentMs: descentTargetMs > 0 ? descentTargetMs : nil)
        operation = Task {
            do {
                for choice in PoseEngineChoice.allCases where choice.isAvailable {
                    try Task.checkCancellation()
                    comparingEngine = choice.title
                    do {
                        let diagnostics = ReplayRunDiagnostics()
                        let value = try await VideoReplayAnalyzer.run(url: localURL, engine: choice, target: target, diagnostics: diagnostics) { [weak self] value in
                            await self?.receive(value, generation: token)
                        }
                        guard generation == token else { return }
                        let report = await diagnostics.report(engine: choice.title, file: sourceName, summary: value)
                        comparisonReports.append(report)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        guard generation == token else { return }
                        comparisonErrors[choice.title] = error.localizedDescription
                    }
                }
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PoseDiagnostics")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("comparison-\(UUID()).json")
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(PoseComparisonExport(createdAt: .now, source: sourceName, reports: comparisonReports, errors: comparisonErrors)).write(to: url, options: .atomic)
                comparisonExportURL = url
            } catch is CancellationError { }
            catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { running = false; comparingEngine = nil }
        }
    }

    private func start(_ url: URL) {
        operation?.cancel(); generation += 1; let token = generation
        snapshot = nil; summary = nil; error = nil; running = true
        evidenceTimeMs = nil
        comparisonReports = []; comparisonExportURL = nil
        comparisonErrors = [:]
        comparingEngine = nil
        let selectedEngine = engineChoice
        let target = SquatTrainingTarget(minimumDescentMs: descentTargetMs > 0 ? descentTargetMs : nil)
        operation = Task {
            do {
                let value = try await VideoReplayAnalyzer.run(url: url, engine: selectedEngine, target: target) { [weak self] value in
                    await self?.receive(value, generation: token)
                }
                guard generation == token else { return }
                summary = value
            } catch is CancellationError { }
            catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { running = false }
        }
    }

    private func receive(_ value: ReplaySnapshot, generation token: Int) {
        if generation == token { snapshot = value }
    }

    func cancel() {
        generation += 1; operation?.cancel(); operation = nil; running = false
        player?.pause(); player = nil; snapshot = nil; summary = nil; error = nil
        evidenceTimeMs = nil
        comparisonReports = []; comparisonExportURL = nil; comparingEngine = nil
        comparisonErrors = [:]
        if let localURL { try? FileManager.default.removeItem(at: localURL) }
        localURL = nil
    }
}
