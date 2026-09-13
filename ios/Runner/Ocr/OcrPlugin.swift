import Flutter
import UIKit
import Vision

/// Flutter-facing entry point for native OCR on iOS (SPEC 9.4). Wraps
/// Vision's `VNRecognizeTextRequest` behind `OcrContract`'s versioned
/// channel. Returns raw per-line results (one per
/// `VNRecognizedTextObservation`); grouping lines into paragraphs and
/// classifying block types happens once, cross-platform, in Dart's
/// `AnalyzeOcrLayoutUseCase` (SPEC 9.4: "Platform OCR output must not be
/// assumed to reconstruct a book automatically").
///
/// Unlike the Android ML Kit adapter, Vision's `VNRecognizedText.confidence`
/// is a genuine per-line confidence score, so this adapter reports real
/// confidence values (see `OcrPlugin.kt` for the documented Android
/// limitation). Per-word bounding boxes are not extracted (Vision only
/// exposes them via range-based `boundingBox(for:)` on the whole recognized
/// string, not attempted here) -- `words` is always empty; layout analysis
/// operates on line-level geometry only, so no block-type classification
/// signal is lost.
public class OcrPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = OcrPlugin()
        let channel = FlutterMethodChannel(
            name: OcrContract.methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case OcrContract.methodSupportedLanguages:
            handleSupportedLanguages(result: result)
        case OcrContract.methodRecognize:
            handleRecognize(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleSupportedLanguages(result: @escaping FlutterResult) {
        do {
            let languages = try VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: .accurate,
                revision: VNRecognizeTextRequestRevision2
            )
            result(languages)
        } catch {
            result(["en"])
        }
    }

    private func handleRecognize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String
        else {
            result(FlutterError(code: OcrContract.errorProcessingFailed, message: "Missing imagePath", details: nil))
            return
        }
        let languages = args["languages"] as? [String] ?? ["en"]

        guard let cgImage = UIImage(contentsOfFile: imagePath)?.cgImage else {
            result(FlutterError(
                code: OcrContract.errorStorageUnavailable,
                message: "Could not load image at \(imagePath)",
                details: nil
            ))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let lines = observations.compactMap { observation -> [String: Any]? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return [
                        "text": candidate.string,
                        "confidence": Double(candidate.confidence),
                        "language": languages.first ?? "",
                        "boundingPolygon": Self.polygon(for: observation.boundingBox),
                        "words": [Any](),
                    ]
                }
                DispatchQueue.main.async {
                    result(["lines": lines])
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: OcrContract.errorProcessingFailed,
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    /// Vision's `boundingBox` is normalized with the origin at the image's
    /// lower-left corner (y increasing upward); the rest of this codebase
    /// (see `FrameMath.swift`) uses a top-left-origin convention (y
    /// increasing downward), so y is flipped here.
    private static func polygon(for box: CGRect) -> [String: Any] {
        let left = Double(box.minX)
        let right = Double(box.maxX)
        let top = 1 - Double(box.maxY)
        let bottom = 1 - Double(box.minY)
        return [
            "points": [
                ["x": left, "y": top],
                ["x": right, "y": top],
                ["x": right, "y": bottom],
                ["x": left, "y": bottom],
            ],
        ]
    }
}
