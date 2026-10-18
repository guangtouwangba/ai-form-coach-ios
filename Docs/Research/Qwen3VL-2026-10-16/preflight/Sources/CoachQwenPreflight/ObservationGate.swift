import Foundation

/// Validates an experimental VLM observation; never certifies a training finding.
/// Trusted cycle evidence must come from the temporal engine, not from this VLM.
public enum ObservationGate {
    public enum CycleEvidence: Sendable { case unavailable, incomplete, completed }
    public struct Context: Sendable {
        public let frameIDs: Set<String>
        public let lateralView: Bool
        public let personDetected: Bool?
        public let staticSequence: Bool?
        public let cycle: CycleEvidence
        public init(frameIDs: Set<String>, lateralView: Bool, personDetected: Bool? = nil,
                    staticSequence: Bool? = nil, cycle: CycleEvidence = .unavailable) {
            self.frameIDs=frameIDs;self.lateralView=lateralView;self.personDetected=personDetected
            self.staticSequence=staticSequence;self.cycle=cycle
        }
    }
    public struct Verdict: Encodable, Sendable {
        public let acceptedAsObservation: Bool
        public let reasons: [String]
        public let normalizedJSON: String?
        /// Observations are research candidates; automatic advice is intentionally disabled.
        public let eligibleForAutomaticCoaching: Bool = false
    }
    public static func validate(_ raw: String, context: Context, truncated: Bool = false) -> Verdict {
        func reject(_ reasons: [String]) -> Verdict {
            .init(acceptedAsObservation:false,reasons:reasons,normalizedJSON:nil)
        }
        guard !truncated else { return reject(["truncated_generation"]) }
        guard raw.utf8.count <= 16_384 else { return reject(["output_too_large"]) }
        var text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        // Accept one complete JSON fence, never extract an arbitrary inner substring.
        if text.hasPrefix("```json\n"),text.hasSuffix("\n```") {
            text=String(text.dropFirst(8).dropLast(4))
        }
        guard let data=text.data(using:.utf8),
              var object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              Set(object.keys)==Set(["motion","lowest_frame","returned","knee_in","explanation"]),
              let motion=object["motion"] as? String,["squat","static","unknown"].contains(motion),
              let returned=object["returned"] as? String,["yes","no","uncertain","unknown"].contains(returned),
              let knee=object["knee_in"] as? String,["yes","no","uncertain","unknown"].contains(knee),
              let explanation=object["explanation"] as? String,!explanation.isEmpty,explanation.count<=400
        else { return reject(["invalid_schema_or_enum"]) }
        guard object["lowest_frame"] is NSNull || object["lowest_frame"] is String else {
            return reject(["invalid_frame_type"])
        }
        let lowest=object["lowest_frame"] as? String
        var reasons:[String]=[]
        if let lowest,!context.frameIDs.contains(lowest) { reasons.append("unknown_frame_reference") }
        if motion != "squat",lowest != nil || returned == "yes" { reasons.append("non_squat_claims_cycle") }
        if context.lateralView,knee == "yes" || knee == "no" { reasons.append("lateral_view_cannot_assess_knee_in") }
        if context.personDetected == false,motion != "unknown" || lowest != nil || returned == "yes" {
            reasons.append("no_person_evidence")
        }
        if context.staticSequence == true,motion == "squat" || lowest != nil || returned == "yes" {
            reasons.append("static_input_claims_motion")
        }
        if context.cycle == .incomplete,returned == "yes" { reasons.append("temporal_engine_disagrees") }
        guard reasons.isEmpty else { return reject(reasons) }
        // These are synonyms for abstention, not correction of a yes/no judgment.
        if knee == "unknown" { object["knee_in"]="uncertain" }
        if returned == "unknown" { object["returned"]="uncertain" }
        let normalized=try? JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
        return .init(acceptedAsObservation:true,reasons:[],normalizedJSON:normalized.map{String(decoding:$0,as:UTF8.self)})
    }
}
