package com.woops.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // View-once photos/videos: block screenshots and screen recording while open.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "woops/secure_screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                "disable" -> { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
