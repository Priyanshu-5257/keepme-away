package io.github.priyanshu5257.keepmeaway

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

class ProtectionService : Service(), FaceDetectionManager.FaceDetectionCallback {

    companion object {
        @Volatile
        var isServiceRunning = false
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "ProtectionServiceChannel"
        private const val ACTION_STOP = "STOP_PROTECTION"
        private const val ACTION_RECALIBRATE = "RECALIBRATE"
        private const val PREFS_FLUTTER = "FlutterSharedPreferences"
    }

    private var windowManager: WindowManager? = null
    private var overlayRoot: LinearLayout? = null
    private var overlayTitle: TextView? = null
    private var overlaySubtitle: TextView? = null
    private var overlayCountdown: TextView? = null
    private var faceDetectionManager: FaceDetectionManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var retryCount = 0
    private val maxRetries = 3
    private var fallbackMode = false

    private var baselineIod = 0.0
    private var thresholdFactor = 1.4
    private var hysteresisGap = 0.12
    private var warningTime = 3
    private var detectionThreshold = 0.5

    private var isWarning = false
    private var isBlocked = false
    private var warningStartTime = 0L
    private var lastSessionFlushElapsed = 0L

    private val countdownTick = object : Runnable {
        override fun run() {
            if (!isWarning || overlayRoot == null) return
            val elapsedSec = ((System.currentTimeMillis() - warningStartTime) / 1000).toInt()
            val remaining = warningTime - elapsedSec
            if (remaining <= 0) {
                isWarning = false
                isBlocked = true
                applyBlockedUi()
                updateNotification("Screen blocked — move back to continue")
                recordBlock()
                return
            }
            overlayCountdown?.text = remaining.toString()
            updateNotification("Move back — $remaining")
            mainHandler.postDelayed(this, 250)
        }
    }

    private val sessionTick = object : Runnable {
        override fun run() {
            flushSessionMinutes(roundUp = false)
            if (isServiceRunning) {
                mainHandler.postDelayed(this, 30_000)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
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
                loadConfig(intent)
                faceDetectionManager?.confidenceThreshold = detectionThreshold.toFloat()
                if (!isServiceRunning) {
                    startForegroundService()
                    startMonitoring()
                } else {
                    updateNotification("Protection active")
                }
                return START_STICKY
            }
        }
    }

    private fun loadConfig(intent: Intent?) {
        val stored = getSharedPreferences("protection_config", MODE_PRIVATE)
        val hasExtras = intent != null &&
            (intent.hasExtra("baselineIod") || intent.hasExtra("baselineArea"))

        if (hasExtras && intent != null) {
            baselineIod = intent.getDoubleExtra(
                "baselineIod",
                intent.getDoubleExtra("baselineArea", 0.0),
            )
            thresholdFactor = intent.getDoubleExtra("thresholdFactor", 1.4)
            hysteresisGap = intent.getDoubleExtra("hysteresisGap", 0.12)
            warningTime = intent.getIntExtra("warningTime", 3)
            detectionThreshold = intent.getDoubleExtra("detectionThreshold", 0.5)
            stored.edit()
                .putFloat("baselineIod", baselineIod.toFloat())
                .putFloat("thresholdFactor", thresholdFactor.toFloat())
                .putFloat("hysteresisGap", hysteresisGap.toFloat())
                .putInt("warningTime", warningTime)
                .putFloat("detectionThreshold", detectionThreshold.toFloat())
                .apply()
        } else {
            baselineIod = stored.getFloat("baselineIod", 0f).toDouble()
            thresholdFactor = stored.getFloat("thresholdFactor", 1.4f).toDouble()
            hysteresisGap = stored.getFloat("hysteresisGap", 0.12f).toDouble()
            warningTime = stored.getInt("warningTime", 3)
            detectionThreshold = stored.getFloat("detectionThreshold", 0.5f).toDouble()
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
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val stopPendingIntent = PendingIntent.getService(
            this, 0,
            Intent(this, ProtectionService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val recalibratePendingIntent = PendingIntent.getService(
            this, 1,
            Intent(this, ProtectionService::class.java).apply { action = ACTION_RECALIBRATE },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("KeepMe Away")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPendingIntent)
            .addAction(android.R.drawable.ic_menu_edit, "Recalibrate", recalibratePendingIntent)
            .build()
    }

    private fun startForegroundService() {
        startForeground(NOTIFICATION_ID, buildNotification("Monitoring your viewing distance"))
        isServiceRunning = true
    }

    private fun startMonitoring() {
        retryCount = 0
        fallbackMode = false
        isWarning = false
        isBlocked = false
        lastSessionFlushElapsed = SystemClock.elapsedRealtime()
        mainHandler.removeCallbacks(sessionTick)
        mainHandler.postDelayed(sessionTick, 30_000)
        faceDetectionManager?.startDetection()
    }

    private fun stopMonitoring() {
        mainHandler.removeCallbacks(sessionTick)
        mainHandler.removeCallbacks(countdownTick)
        flushSessionMinutes(roundUp = true)
        faceDetectionManager?.stopDetection()
    }

    override fun onFaceDetected(result: FaceDetectionResult) {
        mainHandler.post { processDetectionResult(result) }
    }

    override fun onError(error: String) {
        android.util.Log.e("ProtectionService", "Face detection error: $error")
        if (retryCount < maxRetries && !fallbackMode) {
            retryCount++
            updateNotification("Camera issue — retrying ($retryCount/$maxRetries)")
            CoroutineScope(Dispatchers.IO).launch {
                delay(4000)
                try {
                    faceDetectionManager?.stopDetection()
                    delay(1500)
                    faceDetectionManager?.startDetection()
                } catch (e: Exception) {
                    android.util.Log.e("ProtectionService", "Error restarting face detection", e)
                }
            }
        } else {
            fallbackMode = true
            updateNotification("Camera unavailable — protection paused")
        }
    }

    private fun processDetectionResult(result: FaceDetectionResult) {
        if (baselineIod <= 0) return

        val enterThreshold = baselineIod * thresholdFactor
        val exitThreshold = baselineIod * maxOf(thresholdFactor - hysteresisGap, 1.05)
        val currentTime = System.currentTimeMillis()

        if (result.faceDetected && result.iod > enterThreshold) {
            if (!isWarning && !isBlocked) {
                isWarning = true
                warningStartTime = currentTime
                recordWarning()
                showWarningOverlay()
            }
        } else if (!result.faceDetected || result.iod < exitThreshold) {
            if (isWarning || isBlocked) {
                isWarning = false
                isBlocked = false
                hideOverlay()
                updateNotification(
                    if (!result.faceDetected) "Monitoring your viewing distance"
                    else "Comfortable distance restored"
                )
            }
        }
    }

    private fun showWarningOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            updateNotification("Overlay permission required")
            return
        }
        if (!ensureOverlay()) return
        triggerHapticFeedback()
        applyWarningUi()
        mainHandler.removeCallbacks(countdownTick)
        mainHandler.post(countdownTick)
    }

    private fun ensureOverlay(): Boolean {
        if (overlayRoot != null) return true
        try {
            val density = resources.displayMetrics.density
            val column = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(
                    (32 * density).toInt(),
                    (32 * density).toInt(),
                    (32 * density).toInt(),
                    (32 * density).toInt()
                )
            }
            val countdown = TextView(this).apply {
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 96f)
                typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                gravity = Gravity.CENTER
            }
            val title = TextView(this).apply {
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
                typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                gravity = Gravity.CENTER
                setPadding(0, (8 * density).toInt(), 0, 0)
            }
            val subtitle = TextView(this).apply {
                setTextColor(Color.parseColor("#B3FFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                gravity = Gravity.CENTER
                setPadding(0, (12 * density).toInt(), 0, 0)
            }
            column.addView(countdown)
            column.addView(title)
            column.addView(subtitle)

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
            windowManager?.addView(column, params)
            overlayRoot = column
            overlayCountdown = countdown
            overlayTitle = title
            overlaySubtitle = subtitle
            return true
        } catch (e: Exception) {
            updateNotification("Error showing overlay: ${e.message}")
            return false
        }
    }

    private fun applyWarningUi() {
        overlayRoot?.setBackgroundColor(Color.parseColor("#D60B1220"))
        overlayCountdown?.visibility = View.VISIBLE
        val remaining = warningTime.coerceAtLeast(1)
        overlayCountdown?.text = remaining.toString()
        overlayTitle?.text = "A bit close"
        overlaySubtitle?.text = "Move back to keep the screen"
        updateNotification("Move back — $remaining")
    }

    private fun applyBlockedUi() {
        overlayRoot?.setBackgroundColor(Color.parseColor("#F20B1220"))
        overlayCountdown?.visibility = View.GONE
        overlayTitle?.text = "You’re too close"
        overlaySubtitle?.text = "Move back to your comfortable distance.\nThe screen unlocks automatically."
        triggerHapticFeedback()
    }

    private fun hideOverlay() {
        mainHandler.removeCallbacks(countdownTick)
        overlayRoot?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
            }
        }
        overlayRoot = null
        overlayTitle = null
        overlaySubtitle = null
        overlayCountdown = null
    }

    private fun triggerHapticFeedback() {
        try {
            val prefs = getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
            val hapticsEnabled = prefs.getBoolean("flutter.haptics_enabled", true)
            if (!hapticsEnabled) return

            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager =
                    getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createWaveform(longArrayOf(0, 100, 50, 100), -1)
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(longArrayOf(0, 100, 50, 100), -1)
            }
        } catch (_: Exception) {
        }
    }

    private fun recordWarning() {
        try {
            val prefs = flutterPrefs()
            checkAndResetDailyStats(prefs)
            prefs.edit()
                .putLong("flutter.stats_today_warnings", (prefInt(prefs, "flutter.stats_today_warnings") + 1).toLong())
                .putLong("flutter.stats_total_warnings", (prefInt(prefs, "flutter.stats_total_warnings") + 1).toLong())
                .apply()
        } catch (e: Exception) {
            android.util.Log.e("ProtectionService", "Failed to record warning: ${e.message}")
        }
    }

    private fun recordBlock() {
        try {
            val prefs = flutterPrefs()
            checkAndResetDailyStats(prefs)
            prefs.edit()
                .putLong("flutter.stats_today_blocks", (prefInt(prefs, "flutter.stats_today_blocks") + 1).toLong())
                .putLong("flutter.stats_total_blocks", (prefInt(prefs, "flutter.stats_total_blocks") + 1).toLong())
                .apply()
        } catch (e: Exception) {
            android.util.Log.e("ProtectionService", "Failed to record block: ${e.message}")
        }
    }

    private fun flushSessionMinutes(roundUp: Boolean) {
        val now = SystemClock.elapsedRealtime()
        val elapsed = now - lastSessionFlushElapsed
        if (elapsed < 0) {
            lastSessionFlushElapsed = now
            return
        }
        var minutes = (elapsed / 60_000L).toInt()
        val leftover = elapsed % 60_000L
        if (roundUp && leftover >= 15_000L) minutes += 1
        if (minutes <= 0) return
        lastSessionFlushElapsed += minutes * 60_000L
        addSessionMinutes(minutes)
    }

    private fun addSessionMinutes(minutes: Int) {
        try {
            val prefs = flutterPrefs()
            checkAndResetDailyStats(prefs)
            prefs.edit()
                .putLong(
                    "flutter.stats_today_session_minutes",
                    (prefInt(prefs, "flutter.stats_today_session_minutes") + minutes).toLong(),
                )
                .putLong(
                    "flutter.stats_total_session_minutes",
                    (prefInt(prefs, "flutter.stats_total_session_minutes") + minutes).toLong(),
                )
                .apply()
        } catch (e: Exception) {
            android.util.Log.e("ProtectionService", "Failed to record session time: ${e.message}")
        }
    }

    private fun checkAndResetDailyStats(prefs: android.content.SharedPreferences) {
        val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
        val lastDate = prefs.getString("flutter.stats_last_date", "") ?: ""
        if (lastDate == today) return
        if (lastDate.isNotEmpty()) {
            saveDailyToHistory(prefs, lastDate)
        }
        prefs.edit()
            .putLong("flutter.stats_today_warnings", 0)
            .putLong("flutter.stats_today_blocks", 0)
            .putLong("flutter.stats_today_session_minutes", 0)
            .putString("flutter.stats_last_date", today)
            .apply()
    }

    private fun saveDailyToHistory(prefs: android.content.SharedPreferences, date: String) {
        val history = try {
            JSONArray(prefs.getString("flutter.stats_daily_history", "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        if (history.length() > 0) {
            val last = history.optJSONObject(history.length() - 1)
            if (last != null && last.optString("date") == date) return
        }
        history.put(
            JSONObject()
                .put("date", date)
                .put("warnings", prefInt(prefs, "flutter.stats_today_warnings"))
                .put("blocks", prefInt(prefs, "flutter.stats_today_blocks"))
                .put("sessionMinutes", prefInt(prefs, "flutter.stats_today_session_minutes")),
        )
        val trimmed = JSONArray()
        val start = maxOf(0, history.length() - 30)
        for (i in start until history.length()) {
            trimmed.put(history.getJSONObject(i))
        }
        prefs.edit().putString("flutter.stats_daily_history", trimmed.toString()).apply()
    }

    private fun flutterPrefs() = getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)

    /** Flutter shared_preferences stores ints as Long on Android. */
    private fun prefInt(prefs: android.content.SharedPreferences, key: String, default: Int = 0): Int {
        return when (val value = prefs.all[key]) {
            is Int -> value
            is Long -> value.toInt()
            is Float -> value.toInt()
            is Double -> value.toInt()
            else -> default
        }
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun openCalibrationScreen() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("route", "/calibrate")
            }
            startActivity(intent)
        } catch (_: Exception) {
            Toast.makeText(this, "Error opening calibration", Toast.LENGTH_SHORT).show()
        }
    }
}
