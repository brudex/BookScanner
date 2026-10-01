import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registry = engineBridge.pluginRegistry
    CapturePlugin.register(with: registry.registrar(forPlugin: "CapturePlugin")!)
    OcrPlugin.register(with: registry.registrar(forPlugin: "OcrPlugin")!)
    VisionPlugin.register(with: registry.registrar(forPlugin: "VisionPlugin")!)
  }
}
