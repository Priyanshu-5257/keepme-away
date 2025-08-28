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
    private val processingInterval = 500L // Process every 500ms to avoid overload
    
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
        imageReader = ImageReader.newInstance(640, 480, ImageFormat.YUV_420_888, 3)
        imageReader?.setOnImageAvailableListener(onImageAvailableListener, backgroundHandler)
        Log.d(TAG, "ImageReader setup: 640x480 with 3 buffers")
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
        // Throttle processing to avoid overwhelming ML Kit
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastProcessTime < processingInterval) {
            // Skip this frame - too soon since last processing
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
                            // No face detected
                            callback?.onFaceDetected(0.0f)
                            Log.d(TAG, "No faces detected")
                        } else {
                            for (face in faces) {
                                val bounds = face.boundingBox
                                // EXACT same calculation as Flutter
                                val faceArea = bounds.width() * bounds.height()
                                val imageArea = image.width * image.height
                                val relativeArea = faceArea.toDouble() / imageArea.toDouble()
                                totalArea += relativeArea
                                
                                Log.d(TAG, "Android Face detected - Area: $relativeArea, Bounds: ${bounds.width()}x${bounds.height()}, ImageSize: ${image.width}x${image.height}")
                            }
                            
                            // Always report detection result
                            callback?.onFaceDetected(totalArea.toFloat())
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
}
