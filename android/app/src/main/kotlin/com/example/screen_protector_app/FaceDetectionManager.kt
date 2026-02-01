package com.example.screen_protector_app

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Surface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicBoolean

class FaceDetectionManager(private val context: Context) {
    private val TAG = "FaceDetectionManager"
    
    private var cameraManager: CameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    
    private val cameraOpenCloseLock = Semaphore(1)
    private var cameraId: String? = null
    private val isProcessing = AtomicBoolean(false)
    private var lastProcessTime = 0L
    private val processingInterval = 300L // Process every 300ms for balanced battery/responsiveness
    
    // Frame throttling
    private var frameCount = 0
    private val frameSkipCount = 2 // Process every Nth frame
    
    // Adaptive detection
    private var consecutiveStableReadings = 0
    private var lastArea = 0f
    private val stabilityThreshold = 0.05f // 5% change considered stable (increased from 1%)
    private val stableCountForSlowdown = 10
    private var adaptiveSkipMultiplier = 1
    
    // Smoothing - moving average to reduce jitter
    private val recentAreas = mutableListOf<Float>()
    private val smoothingWindowSize = 5 // Average over last 5 readings
    
    // ML Kit face detector with optimized settings
    private val faceDetectorOptions = FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
        .setMinFaceSize(0.15f) // Larger minimum size for better performance
        .setContourMode(FaceDetectorOptions.CONTOUR_MODE_NONE)
        .build()
    
    private val faceDetector = FaceDetection.getClient(faceDetectorOptions)
    
    interface FaceDetectionCallback {
        fun onFaceDetected(area: Float)
        fun onError(error: String)
    }
    
    private var callback: FaceDetectionCallback? = null
    
    fun setCallback(callback: FaceDetectionCallback) {
        this.callback = callback
    }
    
    fun startDetection() {
        Log.d(TAG, "Starting face detection...")
        
        // Ensure clean state first
        stopDetection()
        
        // Add delay to let any previous camera usage finish
        Thread.sleep(2000) // Longer delay for cleanup
        
        startBackgroundThread()
        openCamera()
    }
    
    fun stopDetection() {
        Log.d(TAG, "Stopping face detection...")
        closeCamera()
        stopBackgroundThread()
        isProcessing.set(false)
    }
    
    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("CameraBackground").also { it.start() }
        backgroundHandler = Handler(backgroundThread?.looper!!)
    }
    
    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error stopping background thread", e)
        }
    }
    
    private fun openCamera() {
        try {
            cameraId = getFrontCameraId()
            if (cameraId == null) {
                callback?.onError("No front camera found")
                return
            }
            
            setupImageReader()
            
            if (!cameraOpenCloseLock.tryAcquire(5000, java.util.concurrent.TimeUnit.MILLISECONDS)) {
                Log.e(TAG, "Camera lock timeout - another app might be using camera")
                callback?.onError("Camera busy - please close other camera apps")
                return
            }
            
            Log.d(TAG, "Opening camera $cameraId")
            cameraManager.openCamera(cameraId!!, stateCallback, backgroundHandler)
            
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error opening camera", e)
            callback?.onError("Camera access error: ${e.message}")
            cameraOpenCloseLock.release()
        } catch (e: SecurityException) {
            Log.e(TAG, "Camera permission denied", e)
            callback?.onError("Camera permission denied")
            cameraOpenCloseLock.release()
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected camera error", e)
            callback?.onError("Unexpected camera error: ${e.message}")
            cameraOpenCloseLock.release()
        }
    }
    
    private fun getFrontCameraId(): String? {
        try {
            for (cameraId in cameraManager.cameraIdList) {
                val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
                    return cameraId
                }
            }
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error getting front camera", e)
        }
        return null
    }
    
    private fun setupImageReader() {
        // Use same resolution as Flutter camera for consistency
        // Flutter typically uses the device's default camera resolution
        // For consistency, we'll use a standard resolution
        // Use 320x240 for better battery (face detection doesn't need high resolution)
        // Use 4 buffers to prevent "Unable to acquire buffer" warnings
        imageReader = ImageReader.newInstance(320, 240, ImageFormat.YUV_420_888, 4)
        imageReader?.setOnImageAvailableListener(onImageAvailableListener, backgroundHandler)
        Log.d(TAG, "ImageReader setup: 320x240 with 4 buffers (optimized for battery)")
    }
    
    private val stateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            Log.d(TAG, "Camera opened successfully")
            cameraOpenCloseLock.release()
            cameraDevice = camera
            createCaptureSession()
        }
        
        override fun onDisconnected(camera: CameraDevice) {
            Log.d(TAG, "Camera disconnected")
            cameraOpenCloseLock.release()
            camera.close()
            cameraDevice = null
        }
        
        override fun onError(camera: CameraDevice, error: Int) {
            Log.e(TAG, "Camera error: $error")
            cameraOpenCloseLock.release()
            camera.close()
            cameraDevice = null
            callback?.onError("Camera error: $error")
        }
    }
    
    private fun createCaptureSession() {
        try {
            val surface = imageReader?.surface
            if (surface == null) {
                Log.e(TAG, "ImageReader surface is null")
                return
            }
            
            cameraDevice?.createCaptureSession(
                listOf(surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        Log.d(TAG, "Capture session configured")
                        captureSession = session
                        startRepeatingRequest()
                    }
                    
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "Failed to configure capture session")
                        callback?.onError("Failed to configure camera session")
                    }
                },
                backgroundHandler
            )
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error creating capture session", e)
            callback?.onError("Error creating camera session")
        }
    }
    
    private fun startRepeatingRequest() {
        try {
            val surface = imageReader?.surface ?: return
            
            val captureRequestBuilder = cameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            captureRequestBuilder?.addTarget(surface)
            
            captureSession?.setRepeatingRequest(
                captureRequestBuilder?.build()!!,
                null,
                backgroundHandler
            )
            
            Log.d(TAG, "Started repeating capture request")
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error starting repeating request", e)
        }
    }
    
    private val onImageAvailableListener = ImageReader.OnImageAvailableListener { reader ->
        // Frame skip throttling (battery optimization)
        frameCount++
        val effectiveSkip = frameSkipCount * adaptiveSkipMultiplier
        if (frameCount % effectiveSkip != 0) {
            val image = reader.acquireLatestImage()
            image?.close()
            return@OnImageAvailableListener
        }
        
        // Time-based throttle as backup
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastProcessTime < processingInterval) {
            val image = reader.acquireLatestImage()
            image?.close()
            return@OnImageAvailableListener
        }
        
        // Only process if not already processing
        if (!isProcessing.compareAndSet(false, true)) {
            val image = reader.acquireLatestImage()
            image?.close()
            return@OnImageAvailableListener
        }
        
        try {
            val image = reader.acquireLatestImage()
            if (image != null) {
                lastProcessTime = currentTime
                processImageSafely(image)
            } else {
                isProcessing.set(false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in image listener", e)
            isProcessing.set(false)
        }
    }
    
    private fun processImageSafely(image: Image) {
        try {
            // Handle different camera orientations for front camera
            val inputImage = InputImage.fromMediaImage(image, 270) // Try 270 degrees for front camera
            
            faceDetector.process(inputImage)
                .addOnSuccessListener { faces ->
                    try {
                        var totalArea = 0.0
                        
                        Log.d(TAG, "ML Kit processing - Found ${faces.size} faces")
                        
                        if (faces.isEmpty()) {
                            // No face detected - clear smoothing buffer
                            recentAreas.clear()
                            callback?.onFaceDetected(0.0f)
                            Log.d(TAG, "No faces detected")
                        } else {
                            // Find the largest face (by bounding box area)
                            var largestArea = 0.0
                            for (face in faces) {
                                val bounds = face.boundingBox
                                val faceArea = bounds.width() * bounds.height()
                                val imageArea = image.width * image.height
                                val relativeArea = faceArea.toDouble() / imageArea.toDouble()
                                
                                if (relativeArea > largestArea) {
                                    largestArea = relativeArea
                                }
                            }
                            
                            // Add to smoothing buffer
                            recentAreas.add(largestArea.toFloat())
                            if (recentAreas.size > smoothingWindowSize) {
                                recentAreas.removeAt(0)
                            }
                            
                            // Calculate smoothed area (moving average)
                            val smoothedArea = if (recentAreas.isNotEmpty()) {
                                recentAreas.sum() / recentAreas.size
                            } else {
                                largestArea.toFloat()
                            }
                            
                            Log.d(TAG, "Face detected - Raw: $largestArea, Smoothed: $smoothedArea, Window: ${recentAreas.size}")
                            
                            // Update adaptive mode based on stability
                            updateAdaptiveMode(smoothedArea)
                            
                            // Report smoothed result
                            callback?.onFaceDetected(smoothedArea)
                        }
                        
                    } catch (e: Exception) {
                        Log.e(TAG, "Error processing face detection result", e)
                    } finally {
                        image.close()
                        isProcessing.set(false)
                    }
                }
                .addOnFailureListener { e ->
                    try {
                        Log.e(TAG, "Face detection failed", e)
                        // For failed detection, report no face
                        callback?.onFaceDetected(0.0f)
                    } catch (ex: Exception) {
                        Log.e(TAG, "Error handling detection failure", ex)
                    } finally {
                        image.close()
                        isProcessing.set(false)
                    }
                }
                
        } catch (e: Exception) {
            Log.e(TAG, "Error creating InputImage", e)
            image.close()
            isProcessing.set(false)
        }
    }
    
    private fun closeCamera() {
        try {
            cameraOpenCloseLock.acquire()
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            imageReader?.close()
            imageReader = null
        } catch (e: InterruptedException) {
            throw RuntimeException("Interrupted while trying to lock camera closing.", e)
        } finally {
            cameraOpenCloseLock.release()
        }
    }
    
    private fun updateAdaptiveMode(currentArea: Float) {
        val change = kotlin.math.abs(currentArea - lastArea)
        val relativeChange = if (lastArea > 0) change / lastArea else 1f
        
        if (relativeChange < stabilityThreshold) {
            consecutiveStableReadings++
            if (consecutiveStableReadings >= stableCountForSlowdown) {
                // User is stable, slow down detection to save battery
                adaptiveSkipMultiplier = 2
            }
        } else {
            // Movement detected, speed up detection
            consecutiveStableReadings = 0
            adaptiveSkipMultiplier = 1
        }
        
        lastArea = currentArea
    }
}
