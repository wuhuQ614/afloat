package com.example.smartenglish

import android.content.Intent
import android.os.Build
import android.view.Display
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.smartenglish/framerate"
    private val UPDATE_CHANNEL = "com.smartenglish/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ===== 在线更新：把下载好的 APK 交给系统安装器 =====
        // Android 8+ 需要 REQUEST_INSTALL_PACKAGES 权限（首次会引导用户授权"未知来源"），
        // 且必须用 FileProvider 的 content:// URI（Android 7+ 禁止直接把 file:// 传给其他进程）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath == null) {
                        result.error("bad_args", "apkPath missing", null)
                        return@setMethodCallHandler
                    }
                    val file = File(apkPath)
                    if (!file.exists()) {
                        result.error("file_not_found", "APK 不存在：$apkPath", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setFrameRate" -> {
                    val fps = call.argument<Int>("fps") ?: 60
                    if (fps <= 0) {
                        // fps<=0：解除锁帧，清除首选显示模式，交还系统默认刷新率
                        val clearParams = window.attributes
                        clearParams.preferredDisplayModeId = 0
                        window.attributes = clearParams
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
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
