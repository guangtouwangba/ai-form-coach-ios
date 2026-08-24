import AVFoundation
import Foundation
import SwiftData
import FormCoachCore

final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier == "zh" ? "zh-CN" : "en-US")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
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

    init(summary: WorkoutSummary, config: SessionConfig, startedAt: Date = .now, endedAt: Date = .now, mediaRelativePath: String? = nil) throws {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exerciseID = "bulgarian_split_squat"
        self.variant = config.variant.rawValue
        self.trainingSide = config.trainingSide.rawValue
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
