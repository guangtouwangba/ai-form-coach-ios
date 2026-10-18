import Foundation
import AVFoundation
import CoreImage
import Metal
import Darwin
import CryptoKit
import MLX
import MLXVLM
import MLXLMCommon
import CoachQwenPreflight

struct VideoCase: Codable, Sendable {
    let id: String
    let video: String
    let times: [Double]
    let variant: String?
    let prompt: String
    let maxPixels: Int?
    let maxTokens: Int?
    let systemPrompt: String?
    let prefillChunking: String?
    let referenceVideo: String?
    let referenceTimes: [Double]?
    let lateralView: Bool?
    let exportPreparedTensor: Bool?
    let useExportedPNGForInput: Bool?
}
struct Suite: Codable { let cases: [VideoCase] }

func footprint() -> UInt64 {
    var data = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &data) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? data.phys_footprint : 0
}
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var maximum: UInt64 = 0
    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "coach.footprint"))
    init() {
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
    }
    func sample() { let value = footprint(); lock.lock(); maximum = max(maximum,value); lock.unlock() }
    func reset() { lock.lock(); maximum = 0; lock.unlock(); sample() }
    func peak() -> UInt64 { sample(); lock.lock(); defer { lock.unlock() }; return maximum }
    deinit { timer.cancel() }
}
func snapshot() -> [String: Int] {
    ["activeBytes": Memory.activeMemory, "cacheBytes": Memory.cacheMemory, "peakActiveBytes": Memory.peakMemory]
}
func save(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted,.sortedKeys,.fragmentsAllowed])
    try data.write(to: url, options: .atomic)
}
func monotonicNow() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
func log(_ value: String) {
    FileHandle.standardError.write(Data((value+"\n").utf8))
}

@main struct CoachVideoBenchmark {
    static func main() async {
        do { try await execute() }
        catch { log("BENCHMARK FAILED: \(error)"); exit(1) }
    }
    static func validate(_ item: VideoCase) throws {
        let times=item.times + (item.referenceTimes ?? [])
        guard times.count <= 12, times.allSatisfy({ $0.isFinite && $0 >= 0 }),
              (65_536...262_144).contains(item.maxPixels ?? 262_144),
              (1...192).contains(item.maxTokens ?? 192),
              [nil,"original","static","blank","crop"].contains(item.variant)
        else { throw NSError(domain:"Benchmark",code:2,userInfo:[NSLocalizedDescriptionKey:"Unsafe input budget or unsupported variant: \(item.id)"]) }
    }
    static func execute() async throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Usage: CoachVideoBenchmark <verified model directory> <suite.json> <output directory>")
        }
        let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let suiteURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = try JSONDecoder().decode(Suite.self,from: Data(contentsOf: suiteURL))
        guard !suite.cases.isEmpty else { throw NSError(domain:"Benchmark",code:3,userInfo:[NSLocalizedDescriptionKey:"Empty suite"]) }
        for item in suite.cases { try validate(item) }
        // Cache policy is recorded; do not mistake this for an iOS process memory entitlement.
        Memory.cacheLimit = 128 * 1024 * 1024
        let sampler = FootprintSampler()
        Memory.peakMemory = 0
        let start = monotonicNow()
        log("Loading local verified Qwen3-VL weights")
        let model = try await CoachQwenPreflight.loadLocalWeights(at: modelURL)
        Stream.gpu.synchronize()
        let loadSeconds = (monotonicNow() - start)
        let environment: [String: Any] = [
            "gpu": MTLCreateSystemDefaultDevice()?.name ?? "unknown", "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory, "loadSeconds": loadSeconds,
            "loadPeakFootprintBytes": sampler.peak(), "loadMLX": snapshot(),
            "modelDirectory": modelURL.path, "mlxCacheLimitBytes": Memory.cacheLimit,
            "execution": "real macOS Metal GPU inference; not simulator or iPhone"
        ]
        try save(environment,to: output.appendingPathComponent("environment.json"))
        log("Loaded in \(loadSeconds)s; MLX \(snapshot())")
        var failures = 0
        for item in suite.cases {
            do {
                try await run(item,model: model,base: suiteURL.deletingLastPathComponent(),output: output,sampler: sampler)
            } catch {
                failures += 1
                log("FAILED \(item.id): \(error)")
                try save(["id":item.id,"error":String(describing:error),"success":false],to:output.appendingPathComponent(item.id+".json"))
            }
        }
        guard failures == 0 else { throw NSError(domain:"Benchmark",code:4,userInfo:[NSLocalizedDescriptionKey:"\(failures) inference cases failed; individual errors saved"]) }
    }
    static func run(_ item: VideoCase, model: ModelContainer, base: URL, output: URL, sampler: FootprintSampler) async throws {
        log("CASE \(item.id)")
        sampler.reset(); Memory.peakMemory = 0
        let started = monotonicNow()
        let source = item.video.hasPrefix("/") ? URL(fileURLWithPath:item.video) : base.appendingPathComponent(item.video)
        var images: [UserInput.Image] = []
        var frames: [[String: Any]] = []
        var hashes = Set<String>()
        let captureRoot=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("AIFormCoach/Benchmarks/Qwen3VL-Mac-2026-10-16/captured-frames")
        let frameDirectory = captureRoot.appendingPathComponent(output.lastPathComponent).appendingPathComponent(item.id)
        try FileManager.default.createDirectory(at:frameDirectory,withIntermediateDirectories:true)
        func appendFrames(from source: URL, times: [Double], prefix: String, variant: String?) throws {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url:source))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        for (idx,t) in times.enumerated() {
            var actual = CMTime.zero
            let sampleTime = variant == "static" ? times[0] : t
            let cg = try generator.copyCGImage(at: CMTime(seconds:sampleTime,preferredTimescale:600), actualTime:&actual)
            var image = CIImage(cgImage:cg)
            if variant == "blank" {
                image = CIImage(color: CIColor(red:0.5,green:0.5,blue:0.5)).cropped(to: image.extent)
            }
            if variant == "crop" {
                let e = image.extent
                // Keep upper body only: a controlled observability test, not a posture-error label.
                image = image.cropped(to:CGRect(x:e.minX,y:e.midY,width:e.width,height:e.height/2))
                image = image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY))
            }
            let id = "\(prefix)\(idx+1)"
            let label = "\(id) t=\(String(format:"%.3f",actual.seconds))s"
            let context = CIContext()
            try context.writePNGRepresentation(of:image,to:frameDirectory.appendingPathComponent(id+".png"),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
            if prefix == "F" {
                let png=try Data(contentsOf:frameDirectory.appendingPathComponent(id+".png"))
                hashes.insert(SHA256.hash(data:png).map { String(format:"%02x",$0) }.joined())
            }
            if item.useExportedPNGForInput == true {
                images.append(.url(frameDirectory.appendingPathComponent(id+".png"),label:label))
            } else {
                images.append(.ciImage(image,label:label))
            }
            frames.append(["id":id,"requestedTime":t,"actualTime":actual.seconds,"width":Int(image.extent.width),"height":Int(image.extent.height),"file":frameDirectory.appendingPathComponent(id+".png").path])
        }
        }
        if let reference=item.referenceVideo, let times=item.referenceTimes {
            let url=reference.hasPrefix("/") ? URL(fileURLWithPath:reference) : base.appendingPathComponent(reference)
            try appendFrames(from:url,times:times,prefix:"R",variant:nil)
        }
        try appendFrames(from:source,times:item.times,prefix:"F",variant:item.variant)
        let extractSeconds = (monotonicNow() - started)
        var processing = CoachQwenPreflight.boundedProcessing()
        processing.maxPixels = item.maxPixels ?? 262_144
        var input = UserInput(chat: [
            .system(item.systemPrompt ?? "You are a helpful assistant."),
            .user(item.prompt, images:images)
        ])
        input.processing = processing
        let preparationStart = monotonicNow()
        let prepared = try await model.prepare(input: input)
        eval(prepared.text.tokens)
        if let pixels = prepared.image?.pixels {
            eval(pixels)
            if item.exportPreparedTensor == true {
                try MLX.save(array:pixels,url:frameDirectory.appendingPathComponent("prepared-pixels.npy"))
            }
        }
        Stream.gpu.synchronize()
        let preparationSeconds = (monotonicNow() - preparationStart)
        let tokens = prepared.text.tokens.asArray(Int.self)
        let visualTokenCount = tokens.filter { $0 == 151655 || $0 == 151656 }.count
        let frameShapes = prepared.image?.frames?.map { ["t":$0.t,"h":$0.h,"w":$0.w] } ?? []
        let maxTokens = item.maxTokens ?? 192
        guard tokens.count + maxTokens <= 4096 else { throw NSError(domain:"Benchmark",code:1,userInfo:[NSLocalizedDescriptionKey:"Context budget exceeded: \(tokens.count)+\(maxTokens)"]) }
        let generateStart = monotonicNow()
        let parameters = GenerateParameters(maxTokens:maxTokens,temperature:0,
            prefill:.init(stepSize:512,chunking:item.prefillChunking == "unchunked" ? .unchunked : .balanced))
        let stream = try await model.generate(input:prepared,parameters:parameters)
        var answer = ""
        var firstChunkSeconds: Double?
        var info: [String:Any] = [:]
        for await event in stream {
            switch event {
            case .chunk(let chunk):
                if firstChunkSeconds == nil { firstChunkSeconds = (monotonicNow() - generateStart) }
                answer += chunk
            case .info(let stats):
                info = ["promptTokens":stats.promptTokenCount,"outputTokens":stats.generationTokenCount,
                        "promptSeconds":stats.promptTime,"generationSeconds":stats.generateTime,
                        "tokensPerSecond":stats.tokensPerSecond,"stopReason":String(describing:stats.stopReason)]
            default: break
            }
        }
        Stream.gpu.synchronize()
        let generateSeconds = (monotonicNow() - generateStart)
        var result: [String:Any] = [
            "id":item.id,"success":true,"video":source.path,"variant":item.variant ?? "original",
            "frames":frames,"prompt":item.prompt,"maxPixels":processing.maxPixels!,"maxTokens":maxTokens,
            "inputTokens":tokens.count,"visualTokens":visualTokenCount,"visualGridTHW":frameShapes,
            "decodedPromptTail":await model.decode(tokenIds:Array(tokens.suffix(45))),
            "prefillChunking":item.prefillChunking ?? "balanced",
            "preparedTensorPath":item.exportPreparedTensor == true ? frameDirectory.appendingPathComponent("prepared-pixels.npy").path : "",
            "extractSeconds":extractSeconds,"prepareSeconds":preparationSeconds,"generateWallSeconds":generateSeconds,
            "totalSeconds":(monotonicNow() - started),"firstChunkSeconds":firstChunkSeconds ?? -1,
            "peakFootprintBytes":sampler.peak(),"endFootprintBytes":footprint(),"mlx":snapshot(),
            "generation":info,"rawOutput":answer,"jsonValid":false
        ]
        if let data=answer.data(using:.utf8),let parsed=try? JSONSerialization.jsonObject(with:data) {
            result["parsedOutput"]=parsed; result["jsonValid"]=true
        }
        if let lateral=item.lateralView {
            let ids=Set(frames.compactMap { $0["id"] as? String })
            let context=ObservationGate.Context(frameIDs:ids,lateralView:lateral,
                staticSequence:item.times.count > 1 && hashes.count == 1 ? true : nil)
            let verdict=ObservationGate.validate(answer,context:context,truncated:info["stopReason"] as? String == "length")
            result["observationGate"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(verdict))
            result["identicalQueryFramePixels"]=hashes.count == 1
        }
        // No unvalidated output is converted into a training finding.
        try save(result,to:output.appendingPathComponent(item.id+".json"))
        log("DONE \(item.id) \(String(format:"%.2f",generateSeconds))s; peak \(sampler.peak()); \(answer)")
    }
}
