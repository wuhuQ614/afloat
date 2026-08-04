package com.example.smartenglish

import android.os.Build
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.smartenglish/framerate"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setFrameRate" -> {
                    val fps = call.argument<Int>("fps") ?: 60
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        val display: Display? = windowManager.defaultDisplay
                        val modes: Array<Display.Mode>? = display?.supportedModes
                        if (modes != null && modes.isNotEmpty()) {
                            var bestMode: Display.Mode = modes[0]
                            var bestDiff = Math.abs(bestMode.refreshRate - fps)
                            for (mode in modes) {
                                val diff = Math.abs(mode.refreshRate - fps)
                                if (diff < bestDiff) {
                                    bestDiff = diff
                                    bestMode = mode
                                }
                            }
                            val params = window.attributes
                            params.preferredDisplayModeId = bestMode.modeId
                            window.attributes = params
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
