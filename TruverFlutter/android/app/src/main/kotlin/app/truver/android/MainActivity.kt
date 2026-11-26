package app.truver.android

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // PRD 6: the screen stays on while working (iOS `isIdleTimerDisabled`).
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Debug launch arguments, same as the iOS app's ProcessInfo.arguments:
        //   adb shell am start -n app.truver.android/.MainActivity --es args "-skipOnboarding -tab tuner"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "truver/debug").setMethodCallHandler { call, result ->
            when (call.method) {
                "args" -> result.success(intent?.getStringExtra("args") ?: "")
                else -> result.notImplemented()
            }
        }
    }
}
