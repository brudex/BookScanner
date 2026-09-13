package com.quizfactor.bookscanner.bookscanner

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import com.quizfactor.bookscanner.bookscanner.capture.CapturePlugin
import com.quizfactor.bookscanner.bookscanner.ocr.OcrPlugin

/**
 * Uses [FlutterFragmentActivity] (androidx `FragmentActivity`) rather than
 * the plain `FlutterActivity` because [CapturePlugin] binds CameraX to a
 * `LifecycleOwner`, which only `FragmentActivity`/`ComponentActivity`
 * provide out of the box.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(CapturePlugin())
        flutterEngine.plugins.add(OcrPlugin())
        flutterEngine.plugins.add(com.quizfactor.bookscanner.bookscanner.processing.VisionPlugin())
    }
}
