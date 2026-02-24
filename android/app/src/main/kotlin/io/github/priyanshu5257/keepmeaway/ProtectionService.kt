package io.github.priyanshu5257.keepmeaway

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

class ProtectionService : Service(), FaceDetectionManager.FaceDetectionCallback {
    
    companion object {
        var isServiceRunning = false
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "ProtectionServiceChannel"
        private const val ACTION_STOP = "STOP_PROTECTION"
        private const val ACTION_RECALIBRATE = "RECALIBRATE"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var serviceJob: Job? = null
    private var faceDetectionManager: FaceDetectionManager? = null
    private var retryCount = 0
    private val maxRetries = 3
    private var fallbackMode = false
    
    // Configuration with improved defaults
    private var baselineArea = 0.0
    private var thresholdFactor = 2.0  // Trigger when face area doubles (50% closer)
    private var hysteresisGap = 0.3    // Exit when area drops below 1.7x baseline
    private var warningTime = 3        // 3 second warning
    private var detectionThreshold = 0.5
    
    // Baseline correction mechanism
    private var observedAreas = mutableListOf<Double>()
    private var baselineCorrectionTimer = 0
    private val maxObservedSamples = 20
    private val baselineCorrectionThreshold = 30 // seconds
    private var lastBaselineCheck = 0L
    
    // State
    private var isWarning = false
    private var isBlocked = false
    private var warningStartTime = 0L

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        
        // Initialize face detection manager
        faceDetectionManager = FaceDetectionManager(this).apply {
            setCallback(this@ProtectionService)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_RECALIBRATE -> {
                openCalibrationScreen()
                return START_STICKY
            }
            else -> {
                // Load configuration from intent
                intent?.let {
                    baselineArea = it.getDoubleExtra("baselineArea", 0.0)
                    thresholdFactor = it.getDoubleExtra("thresholdFactor", 1.6)
                    hysteresisGap = it.getDoubleExtra("hysteresisGap", 0.15)
                    warningTime = it.getIntExtra("warningTime", 3)
                    detectionThreshold = it.getDoubleExtra("detectionThreshold", 0.5)
                }
                
                startForegroundService()
                startMonitoring()
                return START_STICKY
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopMonitoring()
        hideOverlay()
        isServiceRunning = false
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Protection Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Screen protection monitoring"
                setSound(null, null)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundService() {
        android.util.Log.d("ProtectionService", "Starting foreground service with baseline: $baselineArea")
        
        val stopIntent = Intent(this, ProtectionService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val recalibrateIntent = Intent(this, ProtectionService::class.java).apply {
            action = ACTION_RECALIBRATE
        }
        val recalibratePendingIntent = PendingIntent.getService(
            this, 1, recalibrateIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Screen Protection Active")
            .setContentText("Monitoring face distance")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .addAction(
                android.R.drawable.ic_media_pause, "Stop", stopPendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_edit, "Recalibrate", recalibratePendingIntent
            )
            .build()

        startForeground(NOTIFICATION_ID, notification)
        isServiceRunning = true
        android.util.Log.d("ProtectionService", "Foreground service started successfully")
    }

    private fun startMonitoring() {
        android.util.Log.d("ProtectionService", "Starting real face detection monitoring")
        
        // Reset state for new session
        retryCount = 0
        fallbackMode = false
        
        // Start the camera-based face detection
        faceDetectionManager?.startDetection()
        
        // Keep a lightweight monitoring job for other tasks
        serviceJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive) {
                try {
                    // Any additional monitoring tasks can go here
                    delay(1000) // Check every second
                } catch (e: Exception) {
                    // Handle errors gracefully
                    updateNotification("Error: ${e.message}")
                    android.util.Log.e("ProtectionService", "Monitoring error", e)
                    delay(5000)
                }
            }
        }
    }

    private fun stopMonitoring() {
        android.util.Log.d("ProtectionService", "Stopping face detection monitoring")
        
        // Stop camera-based face detection
        faceDetectionManager?.stopDetection()
        
        // Cancel any background jobs
        serviceJob?.cancel()
        serviceJob = null
    }

    // Face detection callback implementations
    override fun onFaceDetected(area: Float) {
        val result = FaceDetectionResult(area.toDouble(), area > 0)
        processDetectionResult(result)
    }
    
    override fun onError(error: String) {
        android.util.Log.e("ProtectionService", "Face detection error: $error")
        
        // Only retry if we haven't exceeded max retries
        if (retryCount < maxRetries && !fallbackMode) {
            retryCount++
            android.util.Log.w("ProtectionService", "Retrying face detection (attempt $retryCount/$maxRetries)")
            updateNotification("Camera issue - retrying ($retryCount/$maxRetries)")
            
            CoroutineScope(Dispatchers.IO).launch {
                delay(5000) // Wait longer before retry
                try {
                    faceDetectionManager?.stopDetection()
                    delay(3000) // More time for cleanup
                    faceDetectionManager?.startDetection()
                } catch (e: Exception) {
                    android.util.Log.e("ProtectionService", "Error restarting face detection", e)
                }
            }
        } else {
            android.util.Log.e("ProtectionService", "Switching to fallback mode - camera unavailable")
            fallbackMode = true
            updateNotification("Camera unavailable - protection limited")
            retryCount = 0 // Reset for potential future use
            
            // Start a simple fallback that just monitors for user interaction
            startFallbackMode()
        }
    }
    
    private fun startFallbackMode() {
        android.util.Log.d("ProtectionService", "Starting fallback mode")
        // Simple fallback - could check screen interaction, proximity sensor, etc.
        // For now, just show a warning that camera is unavailable
        updateNotification("Screen protection limited - camera not available")
    }

    private fun processDetectionResult(result: FaceDetectionResult) {
        // Baseline correction mechanism - observe normal usage patterns
        checkAndCorrectBaseline(result)
        
        // Enhanced dynamic threshold logic
        val enterThreshold = baselineArea * thresholdFactor
        val exitThreshold = baselineArea * maxOf(thresholdFactor - hysteresisGap, 1.0)
        
        // Calculate percentage increase from baseline
        val increasePercentage = if (baselineArea > 0) {
            ((result.normalizedArea - baselineArea) / baselineArea * 100)
        } else {
            0.0
        }
        
        android.util.Log.d("ProtectionService", 
            "DETECTION - Face: ${result.faceDetected}, " +
            "Area: ${result.normalizedArea}, " +
            "Baseline: $baselineArea, " +
            "Increase: ${increasePercentage.toInt()}%, " +
            "EnterThreshold: $enterThreshold, " +
            "ExitThreshold: $exitThreshold"
        )
        
        val currentTime = System.currentTimeMillis()
        
        if (result.faceDetected && result.normalizedArea > enterThreshold) {
            // Face detected and too close (area increased significantly)
            if (!isWarning && !isBlocked) {
                // Start warning phase
                isWarning = true
                warningStartTime = currentTime
                updateNotification("Warning: Face ${increasePercentage.toInt()}% closer than baseline!")
                android.util.Log.d("ProtectionService", "WARNING STARTED: Face area increased by ${increasePercentage.toInt()}%")
                recordWarning() // Record statistics
                
            } else if (isWarning && (currentTime - warningStartTime) > (warningTime * 1000)) {
                // Warning period elapsed, activate protection
                isWarning = false
                isBlocked = true
                showOverlay()
                updateNotification("Screen blocked - move back to comfortable distance!")
                android.util.Log.d("ProtectionService", "SCREEN BLOCKED: Face too close for ${warningTime}s")
                recordBlock() // Record statistics
            }
            
        } else if (!result.faceDetected || result.normalizedArea < exitThreshold) {
            // Face not detected OR back to safe distance
            if (isWarning || isBlocked) {
                isWarning = false
                isBlocked = false
                hideOverlay()
                
                val statusMsg = if (!result.faceDetected) {
                    "Monitoring - no face detected"
                } else {
                    "Monitoring - comfortable distance restored"
                }
                
                updateNotification(statusMsg)
                android.util.Log.d("ProtectionService", "SAFE STATE: ${statusMsg}")
            }
        }
        
        // Additional logging for debugging
        if (result.faceDetected) {
            val distanceStatus = when {
                result.normalizedArea > enterThreshold -> "TOO_CLOSE"
                result.normalizedArea < exitThreshold -> "SAFE"
                else -> "BORDERLINE"
            }
            android.util.Log.v("ProtectionService", "Distance status: $distanceStatus")
        }
    }

    private fun showOverlay() {
        if (overlayView != null) return
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            updateNotification("Overlay permission required")
            return
        }
        
        // Haptic feedback - vibrate on warning
        triggerHapticFeedback()

        try {
            overlayView = View(this).apply {
                setBackgroundColor(Color.BLACK)
            }

            val params = WindowManager.LayoutParams().apply {
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.MATCH_PARENT
                type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }
                flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_FULLSCREEN
                format = PixelFormat.TRANSLUCENT
                gravity = Gravity.TOP or Gravity.START
            }

            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            updateNotification("Error showing overlay: ${e.message}")
        }
    }

    private fun hideOverlay() {
        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (e: Exception) {
                // View might already be removed
            }
            overlayView = null
        }
    }
    
    private fun triggerHapticFeedback() {
        try {
            // Check if haptics are enabled in preferences
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val hapticsEnabled = prefs.getBoolean("flutter.haptics_enabled", true)
            
            if (!hapticsEnabled) return
            
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Strong warning vibration pattern
                vibrator.vibrate(VibrationEffect.createWaveform(
                    longArrayOf(0, 100, 50, 100), // delay, vibrate, pause, vibrate
                    -1 // don't repeat
                ))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(longArrayOf(0, 100, 50, 100), -1)
            }
        } catch (e: Exception) {
            // Vibration not available
        }
    }
    
    private fun recordWarning() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            // Check and reset if new day
            checkAndResetDailyStats()
            
            val currentToday = prefs.getInt("flutter.stats_today_warnings", 0)
            val currentTotal = prefs.getInt("flutter.stats_total_warnings", 0)
            
            prefs.edit()
                .putInt("flutter.stats_today_warnings", currentToday + 1)
                .putInt("flutter.stats_total_warnings", currentTotal + 1)
                .apply()
            
            android.util.Log.d("ProtectionService", "STATS: Recorded warning. Today: ${currentToday + 1}, Total: ${currentTotal + 1}")
        } catch (e: Exception) {
            android.util.Log.e("ProtectionService", "Failed to record warning: ${e.message}")
        }
    }
    
    private fun recordBlock() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            
            // Check and reset if new day
            checkAndResetDailyStats()
            
            val currentToday = prefs.getInt("flutter.stats_today_blocks", 0)
            val currentTotal = prefs.getInt("flutter.stats_total_blocks", 0)
            
            prefs.edit()
                .putInt("flutter.stats_today_blocks", currentToday + 1)
                .putInt("flutter.stats_total_blocks", currentTotal + 1)
                .apply()
            
            android.util.Log.d("ProtectionService", "STATS: Recorded block. Today: ${currentToday + 1}, Total: ${currentTotal + 1}")
        } catch (e: Exception) {
            android.util.Log.e("ProtectionService", "Failed to record block: ${e.message}")
        }
    }
    
    private fun checkAndResetDailyStats() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
        val lastDate = prefs.getString("flutter.stats_last_date", "") ?: ""
        
        if (lastDate != today) {
            prefs.edit()
                .putInt("flutter.stats_today_warnings", 0)
                .putInt("flutter.stats_today_blocks", 0)
                .putInt("flutter.stats_today_session_minutes", 0)
                .putString("flutter.stats_last_date", today)
                .apply()
            android.util.Log.d("ProtectionService", "STATS: Reset daily stats for new day: $today")
        }
    }


    private fun updateNotification(text: String) {
        val stopIntent = Intent(this, ProtectionService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val recalibrateIntent = Intent(this, ProtectionService::class.java).apply {
            action = ACTION_RECALIBRATE
        }
        val recalibratePendingIntent = PendingIntent.getService(
            this, 1, recalibrateIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Screen Protection Active")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .addAction(
                android.R.drawable.ic_media_pause, "Stop", stopPendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_edit, "Recalibrate", recalibratePendingIntent
            )
            .build()

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun openCalibrationScreen() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("route", "/calibrate")
            }
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(this, "Error opening calibration", Toast.LENGTH_SHORT).show()
        }
    }

    private fun checkAndCorrectBaseline(result: FaceDetectionResult) {
        // Only collect data when face is detected and not warning/blocking
        if (result.faceDetected && !isWarning && !isBlocked) {
            observedAreas.add(result.normalizedArea)
            
            // Keep only recent samples
            if (observedAreas.size > maxObservedSamples) {
                observedAreas.removeAt(0)
            }
            
            val currentTime = System.currentTimeMillis()
            
            // Check for baseline correction every 30 seconds
            if (currentTime - lastBaselineCheck > (baselineCorrectionThreshold * 1000)) {
                lastBaselineCheck = currentTime
                
                if (observedAreas.size >= 10) {
                    val observedMedian = observedAreas.sorted()[observedAreas.size / 2]
                    
                    // If baseline is significantly different from observed usage, correct it
                    val baselineDifference = Math.abs(observedMedian - baselineArea) / baselineArea
                    
                    if (baselineDifference > 0.5) { // More than 50% difference
                        val oldBaseline = baselineArea
                        // Gradually adjust baseline towards observed median
                        baselineArea = (baselineArea + observedMedian) / 2.0
                        
                        android.util.Log.d("ProtectionService", 
                            "BASELINE CORRECTION: Old: $oldBaseline, " +
                            "Observed: $observedMedian, " +
                            "New: $baselineArea, " +
                            "Difference: ${(baselineDifference * 100).toInt()}%"
                        )
                        
                        updateNotification("Baseline auto-corrected to ${baselineArea.toString().take(6)}")
                    }
                }
            }
        }
    }

    private data class FaceDetectionResult(
        val normalizedArea: Double,
        val faceDetected: Boolean
    )
}
