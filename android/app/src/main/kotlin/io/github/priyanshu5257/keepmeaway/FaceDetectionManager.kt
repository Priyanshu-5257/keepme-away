package io.github.priyanshu5257.keepmeaway

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.io.FileInputStream
import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicBoolean
import org.tensorflow.lite.Interpreter

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
    private val stabilityThreshold = 0.05f // 5% change considered stable
    private val stableCountForSlowdown = 10
    private var adaptiveSkipMultiplier = 1
    
    // Smoothing - moving average to reduce jitter
    private val recentAreas = mutableListOf<Float>()
    private val smoothingWindowSize = 5 // Average over last 5 readings
    
    // TFLite interpreter for BlazeFace model
    private var interpreter: Interpreter? = null
    private val INPUT_SIZE = 128
    
    init {
        loadModel()
    }
    
    private fun loadModel() {
        try {
            val modelBuffer = loadModelFile()
            val options = Interpreter.Options().apply {
                setNumThreads(2)
            }
            interpreter = Interpreter(modelBuffer, options)
            Log.d(TAG, "BlazeFace TFLite model loaded successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading TFLite model", e)
        }
    }
    
    private fun loadModelFile(): MappedByteBuffer {
        val fileDescriptor = context.assets.openFd("flutter_assets/assets/face_detection_short_range.tflite")
        val inputStream = FileInputStream(fileDescriptor.fileDescriptor)
        val fileChannel = inputStream.channel
        val startOffset = fileDescriptor.startOffset
        val declaredLength = fileDescriptor.declaredLength
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
    }
    
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
            val tfliteInterpreter = interpreter
            if (tfliteInterpreter == null) {
                Log.e(TAG, "TFLite interpreter not initialized")
                callback?.onFaceDetected(0.0f)
                image.close()
                isProcessing.set(false)
                return
            }
            
            // Convert YUV image to RGB float array for BlazeFace input
            val inputArray = preprocessImage(image)
            
            // Prepare output buffers for BlazeFace
            // BlazeFace short range outputs:
            // Output 0: [1, 896, 16] - regressors (bounding box coordinates)
            // Output 1: [1, 896, 1] - classificators (confidence scores)
            val regressors = Array(1) { Array(896) { FloatArray(16) } }
            val classificators = Array(1) { Array(896) { FloatArray(1) } }
            
            val outputMap = HashMap<Int, Any>()
            outputMap[0] = regressors
            outputMap[1] = classificators
            
            // Run inference
            tfliteInterpreter.runForMultipleInputsOutputs(arrayOf(inputArray), outputMap)
            
            // Parse results
            var maxConfidence = 0f
            var bestIdx = -1
            
            for (i in 0 until 896) {
                val confidence = sigmoid(classificators[0][i][0])
                if (confidence > maxConfidence) {
                    maxConfidence = confidence
                    bestIdx = i
                }
            }
            
            Log.d(TAG, "TFLite processing - Max confidence: $maxConfidence at idx: $bestIdx")
            
            if (maxConfidence > 0.5f && bestIdx >= 0) {
                // Extract bounding box from regressors
                // BlazeFace uses SSD anchors, the regressor values are offsets
                val anchor = getAnchor(bestIdx)
                
                val cx = regressors[0][bestIdx][0] / INPUT_SIZE + anchor.first
                val cy = regressors[0][bestIdx][1] / INPUT_SIZE + anchor.second
                val w = regressors[0][bestIdx][2] / INPUT_SIZE
                val h = regressors[0][bestIdx][3] / INPUT_SIZE
                
                // Calculate face area relative to image
                val faceArea = (w * h).coerceIn(0f, 1f)
                
                // Add to smoothing buffer
                recentAreas.add(faceArea)
                if (recentAreas.size > smoothingWindowSize) {
                    recentAreas.removeAt(0)
                }
                
                // Calculate smoothed area (moving average)
                val smoothedArea = if (recentAreas.isNotEmpty()) {
                    recentAreas.sum() / recentAreas.size
                } else {
                    faceArea
                }
                
                Log.d(TAG, "Face detected - Raw: $faceArea, Smoothed: $smoothedArea, Confidence: $maxConfidence")
                
                // Update adaptive mode based on stability
                updateAdaptiveMode(smoothedArea)
                
                // Report smoothed result
                callback?.onFaceDetected(smoothedArea)
            } else {
                // No face detected - clear smoothing buffer
                recentAreas.clear()
                callback?.onFaceDetected(0.0f)
                Log.d(TAG, "No faces detected (max confidence: $maxConfidence)")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error processing image with TFLite", e)
            callback?.onFaceDetected(0.0f)
        } finally {
            image.close()
            isProcessing.set(false)
        }
    }
    
    private fun sigmoid(x: Float): Float {
        return (1.0f / (1.0f + Math.exp(-x.toDouble()))).toFloat()
    }
    
    /**
     * Preprocess YUV_420_888 image to float array for BlazeFace input.
     * BlazeFace expects [1, 128, 128, 3] float input normalized to [-1, 1].
     */
    private fun preprocessImage(image: Image): Array<Array<Array<FloatArray>>> {
        val width = image.width
        val height = image.height
        
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer
        
        val yRowStride = image.planes[0].rowStride
        val uvRowStride = image.planes[1].rowStride
        val uvPixelStride = image.planes[1].pixelStride
        
        val inputArray = Array(1) { Array(INPUT_SIZE) { Array(INPUT_SIZE) { FloatArray(3) } } }
        
        val scaleX = width.toFloat() / INPUT_SIZE
        val scaleY = height.toFloat() / INPUT_SIZE
        
        for (y in 0 until INPUT_SIZE) {
            for (x in 0 until INPUT_SIZE) {
                val srcX = (x * scaleX).toInt().coerceIn(0, width - 1)
                val srcY = (y * scaleY).toInt().coerceIn(0, height - 1)
                
                val yIdx = srcY * yRowStride + srcX
                val uvIdx = (srcY / 2) * uvRowStride + (srcX / 2) * uvPixelStride
                
                val yVal = (yBuffer.get(yIdx).toInt() and 0xFF).toFloat()
                val uVal = if (uvIdx < uBuffer.capacity()) (uBuffer.get(uvIdx).toInt() and 0xFF).toFloat() else 128f
                val vVal = if (uvIdx < vBuffer.capacity()) (vBuffer.get(uvIdx).toInt() and 0xFF).toFloat() else 128f
                
                // YUV to RGB conversion
                var r = yVal + 1.370705f * (vVal - 128f)
                var g = yVal - 0.337633f * (uVal - 128f) - 0.698001f * (vVal - 128f)
                var b = yVal + 1.732446f * (uVal - 128f)
                
                r = r.coerceIn(0f, 255f)
                g = g.coerceIn(0f, 255f)
                b = b.coerceIn(0f, 255f)
                
                // Normalize to [-1, 1] for BlazeFace
                inputArray[0][y][x][0] = (r / 127.5f) - 1.0f
                inputArray[0][y][x][1] = (g / 127.5f) - 1.0f
                inputArray[0][y][x][2] = (b / 127.5f) - 1.0f
            }
        }
        
        return inputArray
    }
    
    /**
     * Generate BlazeFace SSD anchors.
     * BlazeFace uses a specific anchor generation scheme.
     */
    private fun getAnchor(index: Int): Pair<Float, Float> {
        // BlazeFace short range uses 2 anchor layers:
        // Layer 0: stride 8, 2 anchors per position -> 16x16x2 = 512 anchors
        // Layer 1: stride 16, 6 anchors per position -> 8x8x6 = 384 anchors
        // Total: 896 anchors
        
        if (index < 512) {
            // Layer 0: 16x16 grid, 2 anchors per cell
            val cellIdx = index / 2
            val gridX = cellIdx % 16
            val gridY = cellIdx / 16
            val cx = (gridX + 0.5f) / 16f
            val cy = (gridY + 0.5f) / 16f
            return Pair(cx, cy)
        } else {
            // Layer 1: 8x8 grid, 6 anchors per cell
            val adjustedIdx = index - 512
            val cellIdx = adjustedIdx / 6
            val gridX = cellIdx % 8
            val gridY = cellIdx / 8
            val cx = (gridX + 0.5f) / 8f
            val cy = (gridY + 0.5f) / 8f
            return Pair(cx, cy)
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
