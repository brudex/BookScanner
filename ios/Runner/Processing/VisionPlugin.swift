import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Path-based still vision. Live frames never cross this channel.
/// OpenCV 4.11 is optional; when the xcframework is not linked this plugin
/// reports unavailable and Dart adapters run the baseline pipeline.
public class VisionPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.quizfactor.bookscanner/vision",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(VisionPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result([
                "available": false,
                "opencvVersion": "4.11.0",
                "algorithmVersion": "1.0.0",
            ])
        case "downscaleStill":
            guard let args = call.arguments as? [String: Any],
                  let source = args["sourcePath"] as? String,
                  let dest = args["outputPath"] as? String,
                  let maxLongSide = args["maxLongSide"] as? Int else {
                result(FlutterError(code: "PROCESSING_FAILED", message: "sourcePath, outputPath, maxLongSide required", details: nil))
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Self.downscale(source: source, dest: dest, maxLongSide: maxLongSide)
                DispatchQueue.main.async { result(outcome) }
            }
        case "detectStill", "enhanceStill", "scoreStill":
            result(FlutterError(
                code: "MODEL_UNAVAILABLE",
                message: "OpenCV xcframework not linked; Dart fallback will run",
                details: nil
            ))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Bounds a saved still so its long side is at most `maxLongSide` px,
    /// applying EXIF orientation. ImageIO's thumbnail path decodes at the
    /// target size, so peak memory stays near the output, not the source.
    /// Copies the file unchanged when it is already small and upright.
    private static func downscale(source: String, dest: String, maxLongSide: Int) -> Any {
        let srcURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: dest)
        guard let imageSource = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return FlutterError(code: "PROCESSING_FAILED", message: "Not a decodable image: \(source)", details: nil)
        }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        if max(width, height) <= maxLongSide && orientation == 1 {
            do {
                if source != dest {
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.copyItem(at: srcURL, to: destURL)
                }
            } catch {
                return FlutterError(code: "STORAGE_UNAVAILABLE", message: error.localizedDescription, details: nil)
            }
            return ["width": width, "height": height, "downscaled": false]
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxLongSide, max(width, height)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return FlutterError(code: "PROCESSING_FAILED", message: "Could not decode \(source)", details: nil)
        }
        let tmpURL = URL(fileURLWithPath: dest + ".tmp")
        guard let destination = CGImageDestinationCreateWithURL(
            tmpURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return FlutterError(code: "PROCESSING_FAILED", message: "Could not create \(dest)", details: nil)
        }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return FlutterError(code: "PROCESSING_FAILED", message: "JPEG encode failed", details: nil)
        }
        do {
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
        } catch {
            return FlutterError(code: "STORAGE_UNAVAILABLE", message: error.localizedDescription, details: nil)
        }
        return ["width": image.width, "height": image.height, "downscaled": true]
    }
}
