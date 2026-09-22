import AVFoundation
import FormCoachCore
import SwiftUI
import UIKit

final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
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

    var observationHandler: ((PoseObservation) async -> Void)?

    private let captureQueue = DispatchQueue(label: "coach.camera.capture", qos: .userInteractive)
    private let stateLock = NSLock()
    private var isProcessingFrame = false
    private var isConfigured = false
    private var requestGeneration = 0
    private let perception: LivePosePerception

    override init() {
        #if MEDIAPIPE_ENABLED && canImport(MediaPipeTasksVision)
        perception = MediaPipePosePerception()
        #else
        perception = AppleVisionPosePerception()
        #endif
        super.init()
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
        captureQueue.async { [weak self] in self?.session.stopRunning() }
        DispatchQueue.main.async { [weak self] in self?.status = .idle }
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
        stateLock.unlock()

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampMs = Int(CMTimeGetSeconds(presentationTime) * 1_000)
        let buffer = SendableSampleBuffer(sampleBuffer)
        Task { [weak self] in
            guard let self else { return }
            defer { finishProcessing() }
            do {
                if let observation = try await perception.process(buffer.value, orientation: .up, timestampMs: timestampMs) {
                    await self.observationHandler?(observation)
                }
            } catch {
                publish(.unavailable("pose_inference_failed"))
            }
        }
    }

    private func publish(_ newStatus: Status) {
        DispatchQueue.main.async { [weak self] in self?.status = newStatus }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
