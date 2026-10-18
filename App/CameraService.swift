import AVFoundation
import FormCoachCore
import SwiftUI
import UIKit

final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case running
        case denied
        case unavailable(String)
    }

    let session = AVCaptureSession()
    @Published private(set) var status: Status = .idle
    @Published private(set) var droppedFrameCount = 0
    @Published private(set) var engineChoice: PoseEngineChoice
    @Published private(set) var analyzedFPS = 0.0
    @Published private(set) var maximumFrameGapMs = 0
    @Published private(set) var inferenceError: String?
    @Published private(set) var isRecordingDiagnostic = false
    @Published private(set) var diagnosticVideoURL: URL?
    @Published private(set) var diagnosticTraceURL: URL?
    @Published private(set) var recordingError: String?

    var observationHandler: ((PoseObservation) async -> Void)?

    private let captureQueue = DispatchQueue(label: "coach.camera.capture", qos: .userInteractive)
    private let stateLock = NSLock()
    private var isProcessingFrame = false
    private var isConfigured = false
    private var requestGeneration = 0
    private var analyzedFrames = 0
    private var perception: LivePosePerception
    private let movieOutput = AVCaptureMovieFileOutput()
    private var recordingSupported = false
    private var recordingRequested = false
    private let diagnosticRecorder = PoseDiagnosticRecorder()
    private var analysisTimes: [Int] = []
    private var lastDiagnosticPublish = 0
    private var largestObservedGap = 0

    // A frame can be analyzed successfully without containing a person.
    // Read-only diagnostics must not confuse that with a stalled camera.
    var processedFrameCount: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return analyzedFrames
    }

    private func recordAnalyzedFrame() {
        stateLock.lock(); analyzedFrames += 1; stateLock.unlock()
    }

    override init() {
        let stored = UserDefaults.standard.string(forKey: "coach.poseEngine").flatMap(PoseEngineChoice.init(rawValue:))
        let choice = stored ?? .recommended
        engineChoice = choice
        perception = choice.makePerception()
        if let path = UserDefaults.standard.string(forKey: "coach.diagnosticVideo") {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PoseDiagnostics").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                diagnosticVideoURL = url
                let trace = url.deletingPathExtension().appendingPathExtension("json")
                if FileManager.default.fileExists(atPath: trace.path) { diagnosticTraceURL = trace }
            }
        }
        super.init()
    }

    func selectEngine(_ choice: PoseEngineChoice) {
        guard !isRecordingDiagnostic else { return }
        UserDefaults.standard.set(choice.rawValue, forKey: "coach.poseEngine")
        stateLock.lock(); requestGeneration += 1; stateLock.unlock()
        captureQueue.async { [self] in
            perception = choice.makePerception()
            analysisTimes = []; lastDiagnosticPublish = 0; largestObservedGap = 0
            DispatchQueue.main.async { self.engineChoice = choice; self.inferenceError = nil; self.analyzedFPS = 0; self.maximumFrameGapMs = 0 }
        }
    }

    func recordDiagnostic(seconds: Double = 20) {
        captureQueue.async { [self] in
            guard recordingSupported, session.isRunning, !movieOutput.isRecording, !recordingRequested else {
                DispatchQueue.main.async { self.recordingError = "相机尚未就绪或当前设备不支持录像，请稍后重试。" }; return
            }
            do {
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PoseDiagnostics", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("capture-\(UUID().uuidString).mov")
                movieOutput.maxRecordedDuration = CMTime(seconds: min(60, max(3, seconds)), preferredTimescale: 600)
                recordingRequested = true
                diagnosticRecorder.start()
                DispatchQueue.main.async { self.isRecordingDiagnostic = true; self.recordingError = nil }
                movieOutput.startRecording(to: url, recordingDelegate: self)
            } catch { DispatchQueue.main.async { self.recordingError = error.localizedDescription } }
        }
    }

    func stopDiagnosticRecording() { captureQueue.async { [self] in if movieOutput.isRecording { movieOutput.stopRecording() } } }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let successful = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        captureQueue.async { [self] in
            recordingRequested = false
            let trace = outputFileURL.deletingPathExtension().appendingPathExtension("json")
            do {
                let data = try diagnosticRecorder.finish()
                if successful { try data.write(to: trace, options: .atomic) }
                DispatchQueue.main.async { [self] in
                    isRecordingDiagnostic = false
                    if successful {
                        diagnosticVideoURL = outputFileURL; diagnosticTraceURL = trace
                        UserDefaults.standard.set(outputFileURL.lastPathComponent, forKey: "coach.diagnosticVideo")
                    } else { recordingError = error?.localizedDescription ?? "录像未成功保存" }
                }
            } catch { DispatchQueue.main.async { self.isRecordingDiagnostic = false; self.recordingError = error.localizedDescription } }
        }
    }

    func start() {
        stateLock.lock()
        requestGeneration += 1
        let ticket = requestGeneration
        stateLock.unlock()
        Task { @MainActor in
            status = .requestingPermission
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard isCurrent(ticket) else { return }
            guard granted else {
                status = .denied
                return
            }
            captureQueue.async { [weak self] in
                guard let self, self.isCurrent(ticket) else { return }
                self.configureAndRun()
            }
        }
    }

    func stop() {
        stateLock.lock(); requestGeneration += 1; stateLock.unlock()
        captureQueue.async { [weak self] in
            guard let self else { return }
            if movieOutput.isRecording { movieOutput.stopRecording() }
            session.stopRunning()
        }
        DispatchQueue.main.async { [weak self] in self?.status = .idle }
    }

    // Connecting a preview to a session can wait for capture configuration or
    // stopRunning. Keep that work on the same serial queue as the session.
    func makePreviewLayer(completion: @escaping @MainActor (AVCaptureVideoPreviewLayer) -> Void) {
        captureQueue.async { [self] in
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            if let connection = layer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            DispatchQueue.main.async { completion(layer) }
        }
    }

    func releasePreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        captureQueue.async { layer.session = nil }
    }

    private func isCurrent(_ ticket: Int) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return ticket == requestGeneration
    }

    private func finishProcessing() {
        stateLock.lock(); defer { stateLock.unlock() }
        isProcessingFrame = false
    }

    private func configureAndRun() {
        analysisTimes = []; lastDiagnosticPublish = 0; largestObservedGap = 0
        DispatchQueue.main.async { self.analyzedFPS = 0; self.maximumFrameGapMs = 0 }
        if !isConfigured {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            defer { session.commitConfiguration() }

            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: camera),
                session.canAddInput(input)
            else {
                publish(.unavailable("camera_unavailable"))
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            guard session.canAddOutput(output) else {
                publish(.unavailable("video_output_unavailable"))
                return
            }
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: captureQueue)
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
                if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            }
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                if let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
                }
                recordingSupported = true
            }
            isConfigured = true
        }

        session.startRunning()
        publish(.running)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        stateLock.lock()
        guard !isProcessingFrame else {
            stateLock.unlock()
            DispatchQueue.main.async { [weak self] in self?.droppedFrameCount += 1 }
            return
        }
        isProcessingFrame = true
        let ticket = requestGeneration
        stateLock.unlock()

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampMs = Int(CMTimeGetSeconds(presentationTime) * 1_000)
        let buffer = SendableSampleBuffer(sampleBuffer)
        let adapter = perception
        Task { [weak self] in
            guard let self else { return }
            defer { finishProcessing() }
            do {
                let observation = try await adapter.process(buffer.value, orientation: .up, timestampMs: timestampMs)
                guard isCurrent(ticket) else { return }
                recordAnalyzedFrame()
                if let observation {
                    diagnosticRecorder.append(observation)
                    captureQueue.async { [self] in
                        if let previous = self.analysisTimes.last {
                            let gap = observation.timestampMs - previous
                            self.largestObservedGap = max(self.largestObservedGap, gap)
                            if observation.timestampMs - self.lastDiagnosticPublish >= 250 {
                                let times = self.analysisTimes.filter { observation.timestampMs - $0 < 2_000 }
                                let fps = times.count > 1 ? Double(times.count - 1) * 1000 / Double(max(1, times.last! - times.first!)) : 0
                                self.lastDiagnosticPublish = observation.timestampMs
                                let maximumGap = self.largestObservedGap
                                DispatchQueue.main.async { self.analyzedFPS = fps; self.maximumFrameGapMs = maximumGap }
                            }
                        }
                        self.analysisTimes.append(observation.timestampMs)
                        self.analysisTimes = self.analysisTimes.filter { observation.timestampMs - $0 < 2_000 }
                    }
                    await self.observationHandler?(observation)
                }
            } catch {
                guard isCurrent(ticket) else { return }
                DispatchQueue.main.async { self.inferenceError = error.localizedDescription }
                publish(.unavailable("pose_inference_failed"))
            }
        }
    }

    private func publish(_ newStatus: Status) {
        DispatchQueue.main.async { [weak self] in self?.status = newStatus }
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraService

    func makeCoordinator() -> CameraService { camera }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        camera.makePreviewLayer { [weak view, camera] layer in
            guard let view, view.isMounted else {
                camera.releasePreviewLayer(layer)
                return
            }
            view.install(layer)
        }
        return view
    }

    // Pose updates redraw SwiftUI frequently; the existing connection stays put.
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: CameraService) {
        uiView.isMounted = false
        if let layer = uiView.previewLayer {
            layer.removeFromSuperlayer()
            coordinator.releasePreviewLayer(layer)
            uiView.previewLayer = nil
        }
    }
}

final class PreviewView: UIView {
    var isMounted = true
    var previewLayer: AVCaptureVideoPreviewLayer?

    func install(_ previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        layer.addSublayer(previewLayer)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}
