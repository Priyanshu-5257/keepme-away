package io.github.priyanshu5257.keepmeaway

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), FaceDetectionManager.FaceDetectionCallback {
    private val CHANNEL = "protection_service"
    private val FACE_DETECTION_CHANNEL = "io.github.priyanshu5257.keepmeaway/face_detection"
    private val OVERLAY_PERMISSION_REQUEST_CODE = 1001

    private var protectionChannel: MethodChannel? = null
    private var calibrationFaceDetector: FaceDetectionManager? = null
    @Volatile
    private var lastCalibrationResult: FaceDetectionResult? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        protectionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        protectionChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments != null) {
                        startProtectionService(arguments, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Arguments required", null)
                    }
                }
                "stop" -> stopProtectionService(result)
                "status" -> result.success(ProtectionService.isServiceRunning)
                "checkOverlayPermission" -> checkOverlayPermission(result)
                "requestOverlayPermission" -> requestOverlayPermission(result)
                "requestIgnoreBatteryOptimizations" -> requestIgnoreBatteryOptimizations(result)
                "showOverlay" -> result.success(true)
                "hideOverlay" -> result.success(true)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FACE_DETECTION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCalibrationMode" -> startCalibrationMode(result)
                    "stopCalibrationMode" -> stopCalibrationMode(result)
                    "getCalibrationSample" -> getCalibrationSample(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startProtectionService(arguments: Map<*, *>, result: MethodChannel.Result) {
        try {
            val baseline = (arguments["baselineIod"] as? Number)
                ?: (arguments["baselineArea"] as? Number)
            val intent = Intent(this, ProtectionService::class.java).apply {
                putExtra("baselineIod", baseline?.toDouble() ?: 0.0)
                putExtra("thresholdFactor", (arguments["thresholdFactor"] as? Number)?.toDouble() ?: 1.4)
                putExtra("hysteresisGap", (arguments["hysteresisGap"] as? Number)?.toDouble() ?: 0.12)
                putExtra("warningTime", (arguments["warningTime"] as? Number)?.toInt() ?: 3)
                putExtra("detectionThreshold", (arguments["detectionThreshold"] as? Number)?.toDouble() ?: 0.5)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("START_ERROR", e.message, null)
        }
    }

    private fun stopProtectionService(result: MethodChannel.Result) {
        try {
            stopService(Intent(this, ProtectionService::class.java))
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_ERROR", e.message, null)
        }
    }

    private fun checkOverlayPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            result.success(Settings.canDrawOverlays(this))
        } else {
            result.success(true)
        }
    }

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST_CODE)
            result.success(true)
        } else {
            result.success(true)
        }
    }

    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
                result.success(true)
            } catch (e: Exception) {
                result.error("BATTERY_ERROR", e.message, null)
            }
        } else {
            result.success(true)
        }
    }

    private fun startCalibrationMode(result: MethodChannel.Result) {
        try {
            lastCalibrationResult = null
            calibrationFaceDetector = FaceDetectionManager(this).apply {
                setCallback(this@MainActivity)
            }
            calibrationFaceDetector?.startDetection()
            result.success(true)
        } catch (e: Exception) {
            result.error("CALIBRATION_START_ERROR", e.message, null)
        }
    }

    private fun stopCalibrationMode(result: MethodChannel.Result) {
        try {
            calibrationFaceDetector?.stopDetection()
            calibrationFaceDetector = null
            lastCalibrationResult = null
            result.success(true)
        } catch (e: Exception) {
            result.error("CALIBRATION_STOP_ERROR", e.message, null)
        }
    }

    private fun getCalibrationSample(result: MethodChannel.Result) {
        try {
            val lastResult = lastCalibrationResult
            if (lastResult != null) {
                result.success(
                    mapOf(
                        "faceDetected" to lastResult.faceDetected,
                        "iod" to lastResult.iod.toDouble(),
                        "leftEyeX" to lastResult.leftEyeX.toDouble(),
                        "leftEyeY" to lastResult.leftEyeY.toDouble(),
                        "rightEyeX" to lastResult.rightEyeX.toDouble(),
                        "rightEyeY" to lastResult.rightEyeY.toDouble(),
                        "confidence" to lastResult.confidence.toDouble(),
                    )
                )
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("CALIBRATION_SAMPLE_ERROR", e.message, null)
        }
    }

    override fun onFaceDetected(result: FaceDetectionResult) {
        lastCalibrationResult = result
    }

    override fun onError(error: String) {
        android.util.Log.e("MainActivity", "Calibration face detection error: $error")
        lastCalibrationResult = FaceDetectionResult(false, 0f)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeOpenCalibration(intent)
    }

    override fun onResume() {
        super.onResume()
        maybeOpenCalibration(intent)
    }

    private fun maybeOpenCalibration(intent: Intent?) {
        if (intent?.getStringExtra("route") == "/calibrate") {
            intent.removeExtra("route")
            protectionChannel?.invokeMethod("openCalibration", null)
        }
    }

    override fun onDestroy() {
        calibrationFaceDetector?.stopDetection()
        calibrationFaceDetector = null
        super.onDestroy()
    }
}
