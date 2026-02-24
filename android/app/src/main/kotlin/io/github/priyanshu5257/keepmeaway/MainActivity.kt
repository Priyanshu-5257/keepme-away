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
    
    // Calibration face detection
    private var calibrationFaceDetector: FaceDetectionManager? = null
    private var lastCalibrationResult: FaceDetectionResult? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Protection service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val arguments = call.arguments as? Map<String, Any>
                    if (arguments != null) {
                        startProtectionService(arguments, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Arguments required", null)
                    }
                }
                "stop" -> {
                    stopProtectionService(result)
                }
                "status" -> {
                    getProtectionStatus(result)
                }
                "checkOverlayPermission" -> {
                    checkOverlayPermission(result)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission(result)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations(result)
                }
                "showOverlay" -> {
                    showOverlay(result)
                }
                "hideOverlay" -> {
                    hideOverlay(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Face detection channel for calibration
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FACE_DETECTION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCalibrationMode" -> {
                    startCalibrationMode(result)
                }
                "stopCalibrationMode" -> {
                    stopCalibrationMode(result)
                }
                "getCalibrationSample" -> {
                    getCalibrationSample(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startProtectionService(arguments: Map<String, Any>, result: MethodChannel.Result) {
        try {
            val intent = Intent(this, ProtectionService::class.java).apply {
                putExtra("baselineArea", arguments["baselineArea"] as? Double ?: 0.0)
                putExtra("thresholdFactor", arguments["thresholdFactor"] as? Double ?: 1.6)
                putExtra("hysteresisGap", arguments["hysteresisGap"] as? Double ?: 0.15)
                putExtra("warningTime", arguments["warningTime"] as? Int ?: 3)
                putExtra("detectionThreshold", arguments["detectionThreshold"] as? Double ?: 0.5)
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
            val intent = Intent(this, ProtectionService::class.java)
            stopService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_ERROR", e.message, null)
        }
    }

    private fun getProtectionStatus(result: MethodChannel.Result) {
        result.success(ProtectionService.isServiceRunning)
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

    private fun showOverlay(result: MethodChannel.Result) {
        // This would be handled by the protection service
        result.success(true)
    }

    private fun hideOverlay(result: MethodChannel.Result) {
        // This would be handled by the protection service
        result.success(true)
    }
    
    // Calibration methods using TFLite face detection
    private fun startCalibrationMode(result: MethodChannel.Result) {
        try {
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
                val sampleData = mapOf(
                    "faceDetected" to lastResult.faceDetected,
                    "normalizedArea" to lastResult.normalizedArea
                )
                result.success(sampleData)
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("CALIBRATION_SAMPLE_ERROR", e.message, null)
        }
    }
    
    // FaceDetectionCallback implementation for calibration
    override fun onFaceDetected(area: Float) {
        lastCalibrationResult = FaceDetectionResult(area.toDouble(), area > 0.0)
    }
    
    override fun onError(error: String) {
        android.util.Log.e("MainActivity", "Calibration face detection error: $error")
        lastCalibrationResult = FaceDetectionResult(0.0, false)
    }
    
    // Data class for calibration results
    private data class FaceDetectionResult(
        val normalizedArea: Double,
        val faceDetected: Boolean
    )
}
