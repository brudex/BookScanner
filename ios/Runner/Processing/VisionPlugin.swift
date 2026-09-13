import Flutter
import UIKit

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
}
