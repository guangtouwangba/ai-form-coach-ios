import Foundation
@main struct GateRegression {
    static func main() throws {
        let context=ObservationGate.Context(frameIDs:["F1","F2","F3","F4","F5","F6"],lateralView:true)
        let good=#"{"motion":"squat","lowest_frame":"F4","returned":"yes","knee_in":"unknown","explanation":"F4 shows the lowest observed pose."}"#
        precondition(ObservationGate.validate(good,context:context).acceptedAsObservation)
        precondition(ObservationGate.validate("```json\n"+good+"\n```",context:context).acceptedAsObservation)
        precondition(!ObservationGate.validate(good,context:context).eligibleForAutomaticCoaching)
        precondition(!ObservationGate.validate(good,context:context,truncated:true).acceptedAsObservation)
        precondition(!ObservationGate.validate(good.replacingOccurrences(of:"F4",with:"F99"),context:context).acceptedAsObservation)
        precondition(!ObservationGate.validate(good.replacingOccurrences(of:#""knee_in":"unknown""#,with:#""knee_in":"yes""#),context:context).acceptedAsObservation)
        precondition(!ObservationGate.validate(good.replacingOccurrences(of:#""motion":"squat""#,with:#""motion":"static""#),context:context).acceptedAsObservation)
        let noPerson=ObservationGate.Context(frameIDs:context.frameIDs,lateralView:true,personDetected:false)
        precondition(!ObservationGate.validate(good,context:noPerson).acceptedAsObservation)
        let incomplete=ObservationGate.Context(frameIDs:context.frameIDs,lateralView:true,cycle:.incomplete)
        precondition(!ObservationGate.validate(good,context:incomplete).acceptedAsObservation)
        precondition(!ObservationGate.validate("Explanation: "+good,context:context).acceptedAsObservation)
        precondition(!ObservationGate.validate(good.replacingOccurrences(of:"squat",with:"squat|static|unknown"),context:context).acceptedAsObservation)
        let directory=URL(fileURLWithPath:CommandLine.arguments[1])
        var captured=0
        for name in ["standing-static","blank-control","cropped-control","ascent-omitted"] {
            let url=directory.appendingPathComponent(name+".json")
            let object=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
            let verdict=ObservationGate.validate(object["rawOutput"] as! String,context:context)
            precondition(!verdict.acceptedAsObservation,"Unsafe captured model output escaped: \(name)")
            captured += 1
        }
        print("PASS: 11 validation checks plus \(captured) captured real model failure regressions; automatic coaching stays disabled.")
    }
}
