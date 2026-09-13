import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    CapturePlugin.register(with: self.registrar(forPlugin: "CapturePlugin")!)
    OcrPlugin.register(with: self.registrar(forPlugin: "OcrPlugin")!)
    VisionPlugin.register(with: self.registrar(forPlugin: "VisionPlugin")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
