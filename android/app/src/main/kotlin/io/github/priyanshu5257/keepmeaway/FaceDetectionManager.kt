package io.github.priyanshu5257.keepmeaway

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.io.FileInputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.hypot
import org.tensorflow.lite.Interpreter

data class FaceDetectionResult(
    val faceDetected: Boolean,
    val iod: Float,
    val leftEyeX: Float = 0f,
    val leftEyeY: Float = 0f,
    val rightEyeX: Float = 0f,
    val rightEyeY: Float = 0f,
    val confidence: Float = 0f,
)

class FaceDetectionManager(private val context: Context) {
    private val TAG = "FaceDetectionManager"

    private var cameraManager: CameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private val cameraOpenCloseLock = Semaphore(1)
    private var cameraId: String? = null
    private val isProcessing = AtomicBoolean(false)
    private var lastProcessTime = 0L
    private val processingInterval = 300L

    private var frameCount = 0
    private val frameSkipCount = 2

    private var consecutiveStableReadings = 0
    private var lastIod = 0f
    private val stabilityThreshold = 0.05f
    private val stableCountForSlowdown = 10
    private var adaptiveSkipMultiplier = 1

    private val recentIods = mutableListOf<Float>()
    private val smoothingWindowSize = 5

    private var interpreter: Interpreter? = null
    private val INPUT_SIZE = 128
    var confidenceThreshold = 0.5f

    // Normalized IOD must look like two distinct eye points on a frontal face.
    private val minIod = 0.02f
    private val maxIod = 0.55f

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
        val fileDescriptor =
            context.assets.openFd("flutter_assets/assets/face_detection_short_range.tflite")
        val inputStream = FileInputStream(fileDescriptor.fileDescriptor)
        val fileChannel = inputStream.channel
        val startOffset = fileDescriptor.startOffset
        val declaredLength = fileDescriptor.declaredLength
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
    }

    interface FaceDetectionCallback {
        fun onFaceDetected(result: FaceDetectionResult)
        fun onError(error: String)
    }

    private var callback: FaceDetectionCallback? = null

    fun setCallback(callback: FaceDetectionCallback) {
        this.callback = callback
    }

    fun startDetection() {
        Log.d(TAG, "Starting face detection...")
        stopDetection()
        try {
            Thread.sleep(400)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        startBackgroundThread()
        openCamera()
    }

    fun stopDetection() {
        Log.d(TAG, "Stopping face detection...")
        closeCamera()
        stopBackgroundThread()
        isProcessing.set(false)
        recentIods.clear()
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
                Log.e(TAG, "Camera lock timeout")
                callback?.onError("Camera busy — close other camera apps and try again")
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
            for (id in cameraManager.cameraIdList) {
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
                    return id
                }
            }
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error getting front camera", e)
        }
        return null
    }

    private fun setupImageReader() {
        imageReader = ImageReader.newInstance(320, 240, ImageFormat.YUV_420_888, 4)
        imageReader?.setOnImageAvailableListener(onImageAvailableListener, backgroundHandler)
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

            @Suppress("DEPRECATION")
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
            val captureRequestBuilder =
                cameraDevice?.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            captureRequestBuilder?.addTarget(surface)
            captureSession?.setRepeatingRequest(
                captureRequestBuilder?.build()!!,
                null,
                backgroundHandler
            )
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error starting repeating request", e)
        }
    }

    private val onImageAvailableListener = ImageReader.OnImageAvailableListener { reader ->
        frameCount++
        val effectiveSkip = frameSkipCount * adaptiveSkipMultiplier
        if (frameCount % effectiveSkip != 0) {
            reader.acquireLatestImage()?.close()
            return@OnImageAvailableListener
        }

        val currentTime = System.currentTimeMillis()
        if (currentTime - lastProcessTime < processingInterval) {
            reader.acquireLatestImage()?.close()
            return@OnImageAvailableListener
        }

        if (!isProcessing.compareAndSet(false, true)) {
            reader.acquireLatestImage()?.close()
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
                callback?.onFaceDetected(FaceDetectionResult(false, 0f))
                return
            }

            val inputArray = preprocessImage(image)
            val regressors = Array(1) { Array(896) { FloatArray(16) } }
            val classificators = Array(1) { Array(896) { FloatArray(1) } }
            val outputMap = HashMap<Int, Any>()
            outputMap[0] = regressors
            outputMap[1] = classificators

            tfliteInterpreter.runForMultipleInputsOutputs(arrayOf(inputArray), outputMap)

            var maxConfidence = 0f
            var bestIdx = -1
            for (i in 0 until 896) {
                val confidence = sigmoid(classificators[0][i][0])
                if (confidence > maxConfidence) {
                    maxConfidence = confidence
                    bestIdx = i
                }
            }

            val parsed = if (maxConfidence > confidenceThreshold && bestIdx >= 0) {
                parseIod(regressors[0][bestIdx], bestIdx, maxConfidence)
            } else {
                null
            }

            if (parsed != null) {
                recentIods.add(parsed.iod)
                if (recentIods.size > smoothingWindowSize) {
                    recentIods.removeAt(0)
                }
                val smoothed = recentIods.average().toFloat()
                updateAdaptiveMode(smoothed)
                callback?.onFaceDetected(parsed.copy(iod = smoothed))
            } else {
                recentIods.clear()
                consecutiveStableReadings = 0
                adaptiveSkipMultiplier = 1
                callback?.onFaceDetected(FaceDetectionResult(false, 0f, confidence = maxConfidence))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing image with TFLite", e)
            callback?.onFaceDetected(FaceDetectionResult(false, 0f))
        } finally {
            image.close()
            isProcessing.set(false)
        }
    }

    /**
     * BlazeFace short-range regressors: [cx, cy, w, h, 6 keypoints * (x, y)].
     * Keypoints: 0 left eye, 1 right eye, 2 nose, 3 mouth, 4 left ear, 5 right ear.
     * IOD is the Euclidean distance between the two eye points in normalized image space.
     */
    private fun parseIod(
        regressor: FloatArray,
        index: Int,
        confidence: Float,
    ): FaceDetectionResult? {
        val anchor = getAnchor(index)

        fun keypoint(k: Int): Pair<Float, Float> {
            val x = regressor[4 + 2 * k] / INPUT_SIZE + anchor.first
            val y = regressor[5 + 2 * k] / INPUT_SIZE + anchor.second
            return x to y
        }

        val (lx, ly) = keypoint(0)
        val (rx, ry) = keypoint(1)

        val inFrame = { x: Float, y: Float -> x in -0.05f..1.05f && y in -0.05f..1.05f }
        if (!inFrame(lx, ly) || !inFrame(rx, ry)) return null

        val iod = hypot(rx - lx, ry - ly)
        if (iod < minIod || iod > maxIod) return null

        return FaceDetectionResult(
            faceDetected = true,
            iod = iod,
            leftEyeX = lx,
            leftEyeY = ly,
            rightEyeX = rx,
            rightEyeY = ry,
            confidence = confidence,
        )
    }

    private fun sigmoid(x: Float): Float {
        return (1.0f / (1.0f + Math.exp(-x.toDouble()))).toFloat()
    }

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
                val uVal =
                    if (uvIdx < uBuffer.capacity()) (uBuffer.get(uvIdx).toInt() and 0xFF).toFloat() else 128f
                val vVal =
                    if (uvIdx < vBuffer.capacity()) (vBuffer.get(uvIdx).toInt() and 0xFF).toFloat() else 128f

                var r = yVal + 1.370705f * (vVal - 128f)
                var g = yVal - 0.337633f * (uVal - 128f) - 0.698001f * (vVal - 128f)
                var b = yVal + 1.732446f * (uVal - 128f)

                r = r.coerceIn(0f, 255f)
                g = g.coerceIn(0f, 255f)
                b = b.coerceIn(0f, 255f)

                inputArray[0][y][x][0] = (r / 127.5f) - 1.0f
                inputArray[0][y][x][1] = (g / 127.5f) - 1.0f
                inputArray[0][y][x][2] = (b / 127.5f) - 1.0f
            }
        }

        return inputArray
    }

    private fun getAnchor(index: Int): Pair<Float, Float> {
        if (index < 512) {
            val cellIdx = index / 2
            val gridX = cellIdx % 16
            val gridY = cellIdx / 16
            return Pair((gridX + 0.5f) / 16f, (gridY + 0.5f) / 16f)
        } else {
            val adjustedIdx = index - 512
            val cellIdx = adjustedIdx / 6
            val gridX = cellIdx % 8
            val gridY = cellIdx / 8
            return Pair((gridX + 0.5f) / 8f, (gridY + 0.5f) / 8f)
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

    private fun updateAdaptiveMode(currentIod: Float) {
        val change = kotlin.math.abs(currentIod - lastIod)
        val relativeChange = if (lastIod > 0) change / lastIod else 1f

        if (relativeChange < stabilityThreshold) {
            consecutiveStableReadings++
            if (consecutiveStableReadings >= stableCountForSlowdown) {
                adaptiveSkipMultiplier = 2
            }
        } else {
            consecutiveStableReadings = 0
            adaptiveSkipMultiplier = 1
        }

        lastIod = currentIod
    }
}
