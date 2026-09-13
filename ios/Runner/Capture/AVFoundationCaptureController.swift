import AVFoundation
import CoreVideo
import Flutter
import UIKit

enum CaptureError: Error {
    case permissionDenied(String)
    case unsupportedDevice(String)
    case processingFailed(String)
}

struct StillCaptureResult {
    let originalImagePath: String
    let quad: Quad?
    let qualityScore: Double
    let warnings: [String]
    let capturedAtMs: Int64
    let confidence: Double
    let analyzedFromStill: Bool
}

struct OpenSessionResult {
    let textureId: Int64
    let previewAspectRatio: Double
}

/// `FlutterTexture` backed by the latest video-data-output pixel buffer.
/// Flutter pulls frames via `copyPixelBuffer()`; we push availability via
/// `textureRegistry.textureFrameAvailable(id)` whenever a new frame lands
/// (SPEC 9.1: "Render the native preview efficiently with the supported
/// Flutter texture/platform-view mechanism").
final class CaptureTexture: NSObject, FlutterTexture {
    private var latestBuffer: CVPixelBuffer?
    private let lock = NSLock()

    func update(_ buffer: CVPixelBuffer) {
        lock.lock()
        latestBuffer = buffer
        lock.unlock()
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = latestBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}

/// Owns the AVFoundation capture session, the live-analysis pipeline, and
/// still capture. Mirrors `CameraXCaptureController.kt`. This is the only
/// class in the iOS app that imports AVFoundation — `CapturePlugin`
/// translates its results into the platform-channel contract, and no Dart
/// code ever sees an AVFoundation type (SPEC 9.1, 9.7).
final class AVFoundationCaptureController: NSObject {
    private let textureRegistry: FlutterTextureRegistry
    private let session = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "bookscanner.capture.session")
    // Serial + always-discards-late-frames (SPEC 9.2: "iOS uses a serial
    // analysis queue and discards late video frames").
    private let analysisQueue = DispatchQueue(label: "bookscanner.capture.analysis")

    private var device: AVCaptureDevice?
    private var texture: CaptureTexture?
    private var textureId: Int64?
    private var previousFrame: LumaFrame?
    private var photoCompletion: ((Result<StillCaptureResult, Error>) -> Void)?
    private var lastAnalysis: FrameAnalysisResult?
    private var lastQualityScore: Double = 0.5

    var onFrameAnalysis: ((FrameAnalysisResult) -> Void)?

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
    }

    private var capturesDir: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("captures", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func hasFlash() -> Bool {
        device?.hasFlash ?? false
    }

    func supportsZoom() -> Bool {
        (device?.activeFormat.videoMaxZoomFactor ?? 1) > 1
    }

    func open(completion: @escaping (Result<OpenSessionResult, Error>) -> Void) {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            completion(.failure(CaptureError.permissionDenied("Camera permission not granted")))
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let id = try self.configureSession()
                DispatchQueue.main.async {
                    completion(.success(OpenSessionResult(textureId: id, previewAspectRatio: 4.0 / 3.0)))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func configureSession() throws -> Int64 {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        else {
            throw CaptureError.unsupportedDevice("No camera available on this device")
        }
        device = camera

        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.unsupportedDevice("Cannot add camera input")
        }
        session.addInput(input)

        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        guard session.canAddOutput(videoDataOutput) else {
            session.commitConfiguration()
            throw CaptureError.unsupportedDevice("Cannot add video data output")
        }
        session.addOutput(videoDataOutput)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CaptureError.unsupportedDevice("Cannot add photo output")
        }
        session.addOutput(photoOutput)

        try camera.lockForConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        camera.unlockForConfiguration()

        session.commitConfiguration()

        let newTexture = CaptureTexture()
        let id = textureRegistry.register(newTexture)
        texture = newTexture
        textureId = id

        if !session.isRunning {
            session.startRunning()
        }

        return id
    }

    func captureStill(completion: @escaping (Result<StillCaptureResult, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                DispatchQueue.main.async {
                    completion(.failure(CaptureError.processingFailed("Session not open")))
                }
                return
            }
            self.waitFor3A()
            self.photoCompletion = completion
            let settings = AVCapturePhotoSettings()
            settings.flashMode = self.photoOutput.supportedFlashModes.contains(.auto) ? .auto : .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func setFlashMode(_ mode: String) {
        guard let device, device.hasTorch else { return }
        sessionQueue.async {
            try? device.lockForConfiguration()
            switch mode {
            case "torch":
                device.torchMode = .on
            default:
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        }
    }

    func setZoom(_ level: Double) {
        guard let device else { return }
        sessionQueue.async {
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8.0)
            let factor = 1.0 + (max(0, min(1, level)) * (maxZoom - 1.0))
            try? device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        }
    }

    func setFocusAndExposurePoint(x: Double, y: Double) {
        guard let device else { return }
        sessionQueue.async {
            let point = CGPoint(x: x, y: y)
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    private func waitFor3A(timeoutMs: Int = 700) {
        let start = Date()
        while Date().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
            if let a = lastAnalysis, a.focusAcceptable, a.exposureAcceptable, a.motionBelowThreshold {
                return
            }
            Thread.sleep(forTimeInterval: 0.04)
        }
    }

    func close() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if let textureId = self.textureId {
                self.textureRegistry.unregisterTexture(textureId)
            }
            self.textureId = nil
            self.texture = nil
            self.previousFrame = nil
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension AVFoundationCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        texture?.update(pixelBuffer)
        if let textureId {
            DispatchQueue.main.async { [weak self] in
                self?.textureRegistry.textureFrameAvailable(textureId)
            }
        }

        guard let frame = FrameMath.extractLuma(from: pixelBuffer) else { return }

        let quad = FrameMath.detectQuad(frame)
        let sharpnessScore = FrameMath.sharpness(frame)
        let avgLuma = FrameMath.averageLuminance(frame)
        let motion = FrameMath.motionScore(previous: previousFrame, current: frame)
        previousFrame = frame

        let focusAcceptable = sharpnessScore >= 60.0
        let exposureAcceptable = avgLuma >= 40.0 && avgLuma <= 235.0
        let motionBelowThreshold = motion < 6.0

        var warnings: [String] = []
        if !focusAcceptable { warnings.append("blur") }
        if avgLuma < 40.0 { warnings.append("lowLight") }
        if avgLuma > 235.0 { warnings.append("glare") }
        if quad == nil { warnings.append("clippedEdges") }

        let result = FrameAnalysisResult(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            documentDetected: quad != nil,
            quad: quad,
            cornersStable: cornerStability(quad),
            motionBelowThreshold: motionBelowThreshold,
            focusAcceptable: focusAcceptable,
            exposureAcceptable: exposureAcceptable,
            warnings: warnings,
            qualityScore: min(1.0, max(0.0, sharpnessScore / 900.0)),
            confidence: quad == nil ? 0 : 0.5
        )
        lastAnalysis = result
        lastQualityScore = min(1.0, max(0.0, sharpnessScore / 900.0))
        onFrameAnalysis?(result)
    }

    private func cornerStability(_ quad: Quad?) -> Bool {
        // Stability across frames is tracked by the Dart ViewModel (SPEC:
        // the same stable-window logic used for both platforms lives once,
        // in `CaptureViewModel`, rather than duplicated per native side).
        // Native code only reports whether a quad exists this frame.
        quad != nil
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension AVFoundationCaptureController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let completion = photoCompletion
        photoCompletion = nil

        if let error {
            completion?(.failure(CaptureError.processingFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion?(.failure(CaptureError.processingFailed("No image data in captured photo")))
            return
        }

        let fileName = "\(UUID().uuidString).jpg"
        let fileURL = capturesDir.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
        } catch {
            completion?(.failure(CaptureError.processingFailed("Could not save capture: \(error.localizedDescription)")))
            return
        }

        var stillQuad: Quad? = nil
        var stillConfidence = 0.0
        var stillScore = lastQualityScore
        var warnings: [String] = []
        if let image = UIImage(contentsOfFile: fileURL.path), let cg = image.cgImage,
           let frame = FrameMath.extractLuma(from: cg) {
            stillQuad = FrameMath.detectQuad(frame)
            stillScore = min(1.0, max(0.0, FrameMath.sharpness(frame) / 900.0))
            if stillQuad != nil { stillConfidence = 0.5 }
            let avg = FrameMath.averageLuminance(frame)
            if FrameMath.sharpness(frame) < 60 { warnings.append("blur") }
            if avg < 40 { warnings.append("lowLight") }
            if avg > 235 { warnings.append("glare") }
            if stillQuad == nil { warnings.append("clippedEdges") }
        }
        completion?(.success(StillCaptureResult(
            originalImagePath: fileURL.path,
            quad: stillQuad,
            qualityScore: stillScore,
            warnings: warnings,
            capturedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            confidence: stillConfidence,
            analyzedFromStill: true
        )))
    }
}

struct FrameAnalysisResult {
    let timestampMs: Int64
    let documentDetected: Bool
    let quad: Quad?
    let cornersStable: Bool
    let motionBelowThreshold: Bool
    let focusAcceptable: Bool
    let exposureAcceptable: Bool
    let warnings: [String]
    let qualityScore: Double
    let confidence: Double
}
