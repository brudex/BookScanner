import Flutter
import UIKit

/// Flutter-facing entry point for native capture on iOS. Wires the
/// versioned method/event channel contract in `CaptureContract` to
/// `AVFoundationCaptureController`. Mirrors `CapturePlugin.kt` exactly so
/// Flutter code sees identical behavior from either platform (SPEC 9.1,
/// 9.7).
public class CapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var controller: AVFoundationCaptureController?
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = CapturePlugin()
        let methodChannel = FlutterMethodChannel(
            name: CaptureContract.methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: CaptureContract.analysisEventChannelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)

        let controller = AVFoundationCaptureController(textureRegistry: registrar.textures())
        controller.onFrameAnalysis = { [weak instance] result in
            instance?.dispatch(result)
        }
        instance.controller = controller
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let controller else {
            result(FlutterError(code: CaptureContract.errorUnsupportedDevice, message: "Controller unavailable", details: nil))
            return
        }

        switch call.method {
        case CaptureContract.methodCapabilities:
            result([
                "liveEdgeDetection": true,
                "offlineOcr": false,
                "handwritingOcr": false,
                "bookDewarping": false,
                "fingerRemoval": false,
                "supportedOcrLanguages": [String](),
                "torch": controller.hasFlash(),
                "opticalZoom": controller.supportsZoom(),
            ])

        case CaptureContract.methodOpenSession:
            controller.open { res in
                switch res {
                case let .success(session):
                    result([
                        "textureId": session.textureId,
                        "previewAspectRatio": session.previewAspectRatio,
                    ])
                case let .failure(error):
                    result(Self.flutterError(for: error))
                }
            }

        case CaptureContract.methodCaptureStill:
            controller.captureStill { res in
                switch res {
                case let .success(still):
                    result([
                        "originalImagePath": still.originalImagePath,
                        "detectedQuad": still.quad?.asDict ?? NSNull(),
                        "qualityScore": still.qualityScore,
                        "warnings": still.warnings,
                        "capturedAtMs": still.capturedAtMs,
                        "providerName": CaptureContract.providerName,
                        "adapterVersion": CaptureContract.adapterVersion,
                        "modelVersion": NSNull(),
                        "detectionConfidence": still.confidence,
                        "analyzedFromStill": still.analyzedFromStill,
                    ])
                case let .failure(error):
                    result(Self.flutterError(for: error))
                }
            }

        case CaptureContract.methodSetFlashMode:
            let mode = (call.arguments as? [String: Any])?["mode"] as? String ?? "off"
            controller.setFlashMode(mode)
            result(nil)

        case CaptureContract.methodSetZoom:
            let level = (call.arguments as? [String: Any])?["level"] as? Double ?? 0
            controller.setZoom(level)
            result(nil)

        case CaptureContract.methodSetFocusExposurePoint:
            let args = call.arguments as? [String: Any]
            let x = args?["x"] as? Double ?? 0.5
            let y = args?["y"] as? Double ?? 0.5
            controller.setFocusAndExposurePoint(x: x, y: y)
            result(nil)

        case CaptureContract.methodCloseSession:
            controller.close()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func flutterError(for error: Error) -> FlutterError {
        switch error {
        case let CaptureError.permissionDenied(message):
            return FlutterError(code: CaptureContract.errorPermissionDenied, message: message, details: nil)
        case let CaptureError.unsupportedDevice(message):
            return FlutterError(code: CaptureContract.errorUnsupportedDevice, message: message, details: nil)
        case let CaptureError.processingFailed(message):
            return FlutterError(code: CaptureContract.errorProcessingFailed, message: message, details: nil)
        default:
            return FlutterError(code: CaptureContract.errorProcessingFailed, message: error.localizedDescription, details: nil)
        }
    }

    private func dispatch(_ analysis: FrameAnalysisResult) {
        guard let eventSink else { return }
        DispatchQueue.main.async {
            eventSink([
                "timestampMs": analysis.timestampMs,
                "documentDetected": analysis.documentDetected,
                "quad": analysis.quad?.asDict ?? NSNull(),
                "cornersStable": analysis.cornersStable,
                "motionBelowThreshold": analysis.motionBelowThreshold,
                "focusAcceptable": analysis.focusAcceptable,
                "exposureAcceptable": analysis.exposureAcceptable,
                "warnings": analysis.warnings,
                "qualityScore": analysis.qualityScore,
                "confidence": analysis.confidence,
            ])
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
