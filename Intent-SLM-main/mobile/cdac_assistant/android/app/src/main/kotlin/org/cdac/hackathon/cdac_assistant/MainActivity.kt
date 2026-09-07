package org.cdac.hackathon.cdac_assistant

import android.Manifest
import java.util.concurrent.atomic.AtomicBoolean
import android.view.Surface
import android.os.HandlerThread
import android.os.Environment
import android.media.ImageReader
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraCaptureSession
import android.graphics.ImageFormat
import android.content.ContentValues
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.os.Build
import android.provider.MediaStore
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL =
            "org.cdac.hackathon.cdac_assistant/device_actions"

        private const val CAMERA_PERMISSION_REQUEST = 5001
        private const val CAMERA_CAPTURE_PERMISSION_REQUEST = 5004
        private const val AUDIO_PERMISSION_REQUEST = 5002
        private const val CONTACTS_PERMISSION_REQUEST = 5003
    }

    private var pendingTorchResult: MethodChannel.Result? = null
    private var pendingTorchEnabled: Boolean = false


    private var pendingPhotoCaptureResult:
        MethodChannel.Result? = null

    private var pendingPhotoCaptureFront:
        Boolean = false

    private var pendingMusicResult: MethodChannel.Result? = null
    private var pendingMusicQuery: String = ""

    private var localMediaPlayer: MediaPlayer? = null


    private var pendingWhatsAppResult:
        MethodChannel.Result? = null

    private var pendingWhatsAppContact:
        String = ""

    private var pendingWhatsAppMessage:
        String = ""


    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            try {
                when (call.method) {

                    "openCamera" -> {
                        result.success(openCamera())
                    }

                    "openCalculator" -> {
                        result.success(openCalculator())
                    }

                    "openBrowser" -> {
                        result.success(openBrowser())
                    }

                    "playMusic" -> {
                        val query =
                            call.argument<String>("query")
                                ?.trim()
                                ?: ""

                        handlePlayMusic(
                            query,
                            result
                        )
                    }

                    "pauseMusic" -> {
                        result.success(
                            pauseLocalMusic()
                        )
                    }

                    "resumeMusic" -> {
                        result.success(
                            resumeLocalMusic()
                        )
                    }

                    "stopMusic" -> {
                        result.success(
                            stopLocalMusic()
                        )
                    }

                    "captureFrontPhoto" -> {
                        handlePhotoCapture(
                            true,
                            result
                        )
                    }

                    "captureBackPhoto" -> {
                        handlePhotoCapture(
                            false,
                            result
                        )
                    }

                    "sendWhatsApp" -> {
                        val contact =
                            call.argument<String>(
                                "contact"
                            )?.trim() ?: ""

                        val message =
                            call.argument<String>(
                                "message"
                            )?.trim() ?: ""

                        handleWhatsApp(
                            contact,
                            message,
                            result
                        )
                    }

                    "setFlashlight" -> {
                        val enabled =
                            call.argument<Boolean>("enabled")
                                ?: false

                        handleFlashlight(
                            enabled,
                            result
                        )
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                result.error(
                    "DEVICE_ACTION_FAILED",
                    e.message ?: e.javaClass.simpleName,
                    null
                )
            }
        }
    }


    private fun openCamera(): String {
        try {
            val intent = Intent(
                MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA
            )

            startActivity(intent)

            return "Camera opened"
        } catch (e: ActivityNotFoundException) {
            val fallback =
                Intent(MediaStore.ACTION_IMAGE_CAPTURE)

            startActivity(fallback)

            return "Camera opened"
        }
    }


    private fun openCalculator(): String {

        /*
         * First try OEM calculator packages.
         *
         * Your phone is Oplus/Realme based, so
         * com.coloros / com.oplus are intentionally
         * checked first.
         */
        val calculatorPackages = listOf(
            "com.coloros.calculator",
            "com.oplus.calculator",
            "com.android.calculator2",
            "com.google.android.calculator",
            "com.oneplus.calculator",
            "com.miui.calculator",
            "com.sec.android.app.popupcalculator"
        )

        for (packageName in calculatorPackages) {
            val launchIntent =
                packageManager
                    .getLaunchIntentForPackage(
                        packageName
                    )

            if (launchIntent != null) {
                launchIntent.addFlags(
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                )

                startActivity(launchIntent)

                return "Calculator opened"
            }
        }

        /*
         * Second attempt:
         * Android standard calculator category.
         */
        val standardIntent =
            Intent.makeMainSelectorActivity(
                Intent.ACTION_MAIN,
                Intent.CATEGORY_APP_CALCULATOR
            )

        if (
            standardIntent.resolveActivity(
                packageManager
            ) != null
        ) {
            startActivity(standardIntent)

            return "Calculator opened"
        }

        /*
         * Last fallback:
         * Look through launcher activities and
         * find one whose label/package resembles
         * calculator.
         */
        val launcherIntent =
            Intent(Intent.ACTION_MAIN)
                .addCategory(
                    Intent.CATEGORY_LAUNCHER
                )

        @Suppress("DEPRECATION")
        val activities =
            packageManager.queryIntentActivities(
                launcherIntent,
                0
            )

        val calculatorActivity =
            activities.firstOrNull { info ->

                val label =
                    info.loadLabel(packageManager)
                        .toString()
                        .lowercase()

                val packageName =
                    info.activityInfo
                        .packageName
                        .lowercase()

                label.contains("calculator") ||
                    label == "calc" ||
                    packageName.contains(
                        "calculator"
                    )
            }

        if (calculatorActivity != null) {

            val intent =
                Intent(Intent.ACTION_MAIN)
                    .addCategory(
                        Intent.CATEGORY_LAUNCHER
                    )
                    .setClassName(
                        calculatorActivity
                            .activityInfo
                            .packageName,

                        calculatorActivity
                            .activityInfo
                            .name
                    )

            startActivity(intent)

            return "Calculator opened"
        }

        throw ActivityNotFoundException(
            "Calculator app was not found on this device."
        )
    }


    private fun openBrowser(): String {
        val intent =
            Intent.makeMainSelectorActivity(
                Intent.ACTION_MAIN,
                Intent.CATEGORY_APP_BROWSER
            )

        if (
            intent.resolveActivity(
                packageManager
            ) == null
        ) {
            throw ActivityNotFoundException(
                "No browser application found."
            )
        }

        startActivity(intent)

        return "Browser opened"
    }


    private fun dispatchMediaPlay() {
        val audioManager =
            getSystemService(
                Context.AUDIO_SERVICE
            ) as AudioManager

        audioManager.dispatchMediaKeyEvent(
            KeyEvent(
                KeyEvent.ACTION_DOWN,
                KeyEvent.KEYCODE_MEDIA_PLAY
            )
        )

        audioManager.dispatchMediaKeyEvent(
            KeyEvent(
                KeyEvent.ACTION_UP,
                KeyEvent.KEYCODE_MEDIA_PLAY
            )
        )
    }


    private data class LocalAudioMatch(
        val uri: Uri,
        val title: String,
        val artist: String,
        val displayName: String,
        val score: Int
    )


    private fun handlePlayMusic(
        query: String,
        result: MethodChannel.Result
    ) {

        /*
         * Champion V4 has already predicted
         * PlayMusic before this method runs.
         *
         * Android 13+ requires READ_MEDIA_AUDIO
         * to access music stored by the user.
         */

        val permission =
            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.TIRAMISU
            ) {
                Manifest.permission.READ_MEDIA_AUDIO
            } else {
                Manifest.permission.READ_EXTERNAL_STORAGE
            }


        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.M &&
            checkSelfPermission(
                permission
            ) != PackageManager.PERMISSION_GRANTED
        ) {

            pendingMusicQuery =
                query

            pendingMusicResult =
                result

            requestPermissions(
                arrayOf(
                    permission
                ),
                AUDIO_PERMISSION_REQUEST
            )

            return
        }


        performLocalMusicPlayback(
            query,
            result
        )
    }


    private fun normalizeMusicText(
        value: String
    ): String {

        return value
            .lowercase()
            .replace(
                Regex(
                    "[^\\p{L}\\p{N}]+"
                ),
                " "
            )
            .trim()
    }


    private fun findBestLocalAudio(
        query: String
    ): LocalAudioMatch? {

        val collection =
            MediaStore.Audio.Media
                .EXTERNAL_CONTENT_URI

        val projection =
            arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.DISPLAY_NAME
            )

        val selection =
            "${MediaStore.Audio.Media.IS_MUSIC} != 0"

        val normalizedQuery =
            normalizeMusicText(
                query
            )

        val queryTerms =
            normalizedQuery
                .split(" ")
                .filter {
                    it.length >= 2
                }


        var best:
            LocalAudioMatch? = null


        contentResolver.query(
            collection,
            projection,
            selection,
            null,
            null
        )?.use { cursor ->

            val idColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media._ID
                )

            val titleColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.TITLE
                )

            val artistColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.ARTIST
                )

            val displayColumn =
                cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.DISPLAY_NAME
                )


            while (
                cursor.moveToNext()
            ) {

                val id =
                    cursor.getLong(
                        idColumn
                    )

                val title =
                    cursor.getString(
                        titleColumn
                    )
                        ?: ""

                val artist =
                    cursor.getString(
                        artistColumn
                    )
                        ?: ""

                val displayName =
                    cursor.getString(
                        displayColumn
                    )
                        ?: ""


                val normalizedTitle =
                    normalizeMusicText(
                        title
                    )

                val normalizedArtist =
                    normalizeMusicText(
                        artist
                    )

                val normalizedDisplay =
                    normalizeMusicText(
                        displayName
                    )

                val combined =
                    "$normalizedTitle " +
                    "$normalizedArtist " +
                    normalizedDisplay


                var score = 0


                /*
                 * Exact/large substring matches
                 * receive the highest score.
                 */

                if (
                    normalizedQuery.isNotEmpty()
                ) {

                    if (
                        normalizedTitle.contains(
                            normalizedQuery
                        )
                    ) {
                        score += 120
                    }

                    if (
                        normalizedArtist.contains(
                            normalizedQuery
                        )
                    ) {
                        score += 110
                    }

                    if (
                        normalizedDisplay.contains(
                            normalizedQuery
                        )
                    ) {
                        score += 100
                    }


                    /*
                     * Also support queries such as:
                     *
                     * "set fire to the rain adele"
                     *
                     * where each query word may occur
                     * in a different metadata field.
                     */

                    for (
                        term in queryTerms
                    ) {

                        if (
                            combined.contains(
                                term
                            )
                        ) {
                            score += 20
                        }
                    }


                    /*
                     * Require at least one real match.
                     */

                    if (score == 0) {
                        continue
                    }

                } else {

                    /*
                     * Generic "play music":
                     * prefer real music over recordings.
                     */

                    score =
                        if (
                            normalizedDisplay
                                .contains(
                                    "recording"
                                )
                        ) {
                            1
                        } else {
                            10
                        }
                }


                val uri =
                    ContentUris
                        .withAppendedId(
                            collection,
                            id
                        )


                val candidate =
                    LocalAudioMatch(
                        uri = uri,
                        title = title,
                        artist = artist,
                        displayName = displayName,
                        score = score
                    )


                if (
                    best == null ||
                    candidate.score >
                    best!!.score
                ) {
                    best = candidate
                }
            }
        }


        return best
    }


    private fun performLocalMusicPlayback(
        query: String,
        result: MethodChannel.Result
    ) {

        try {

            val match =
                findBestLocalAudio(
                    query
                )


            if (match == null) {

                result.success(
                    if (
                        query.isNotBlank()
                    ) {
                        "No local music found matching: $query"
                    } else {
                        "No local music files were found"
                    }
                )

                return
            }


            /*
             * Stop/release any track currently
             * being played by this app.
             */

            try {
                localMediaPlayer
                    ?.stop()
            } catch (_: Exception) {
            }

            try {
                localMediaPlayer
                    ?.release()
            } catch (_: Exception) {
            }

            localMediaPlayer =
                null


            val player =
                MediaPlayer()


            player.setAudioAttributes(
                AudioAttributes
                    .Builder()
                    .setUsage(
                        AudioAttributes
                            .USAGE_MEDIA
                    )
                    .setContentType(
                        AudioAttributes
                            .CONTENT_TYPE_MUSIC
                    )
                    .build()
            )


            player.setDataSource(
                this,
                match.uri
            )

            player.prepare()

            player.start()


            player.setOnCompletionListener {
                try {
                    it.release()
                } catch (_: Exception) {
                }

                if (
                    localMediaPlayer === it
                ) {
                    localMediaPlayer =
                        null
                }
            }


            localMediaPlayer =
                player


            val description =
                when {

                    match.artist.isNotBlank() &&
                    match.artist !=
                    "<unknown>" -> {
                        "${match.title} — ${match.artist}"
                    }

                    match.title.isNotBlank() -> {
                        match.title
                    }

                    else -> {
                        match.displayName
                    }
                }


            result.success(
                "Playing local music: $description"
            )

        } catch (
            e: Exception
        ) {

            result.error(
                "LOCAL_MUSIC_FAILED",
                e.message
                    ?: e.javaClass.simpleName,
                null
            )
        }
    }


    private fun pauseLocalMusic(): String {

        val player =
            localMediaPlayer
                ?: return "No local music is currently loaded"

        return try {

            if (player.isPlaying) {

                player.pause()

                "Music paused"

            } else {

                "Music is already paused"
            }

        } catch (
            e: Exception
        ) {

            "Unable to pause music: " +
                (
                    e.message
                        ?: e.javaClass.simpleName
                )
        }
    }


    private fun resumeLocalMusic(): String {

        val player =
            localMediaPlayer
                ?: return "No paused local music is available"

        return try {

            if (!player.isPlaying) {

                player.start()

                "Music resumed"

            } else {

                "Music is already playing"
            }

        } catch (
            e: Exception
        ) {

            "Unable to resume music: " +
                (
                    e.message
                        ?: e.javaClass.simpleName
                )
        }
    }


    private fun stopLocalMusic(): String {

        val player =
            localMediaPlayer
                ?: return "No local music is currently playing"

        return try {

            try {
                player.stop()
            } catch (_: Exception) {
            }

            player.release()

            localMediaPlayer =
                null

            "Music stopped"

        } catch (
            e: Exception
        ) {

            localMediaPlayer =
                null

            "Unable to stop music: " +
                (
                    e.message
                        ?: e.javaClass.simpleName
                )
        }
    }


    private fun handlePhotoCapture(
        frontCamera: Boolean,
        result: MethodChannel.Result
    ) {

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.M &&
            checkSelfPermission(
                Manifest.permission.CAMERA
            ) !=
            PackageManager.PERMISSION_GRANTED
        ) {

            pendingPhotoCaptureFront =
                frontCamera

            pendingPhotoCaptureResult =
                result

            requestPermissions(
                arrayOf(
                    Manifest.permission.CAMERA
                ),
                CAMERA_CAPTURE_PERMISSION_REQUEST
            )

            return
        }

        capturePhoto(
            frontCamera,
            result
        )
    }


    private fun saveCapturedPhoto(
        bytes: ByteArray,
        frontCamera: Boolean
    ): String {

        val prefix =
            if (frontCamera) {
                "CDAC_FRONT"
            } else {
                "CDAC_BACK"
            }

        val fileName =
            "${prefix}_${System.currentTimeMillis()}.jpg"

        val values =
            ContentValues().apply {

                put(
                    MediaStore.Images.Media.DISPLAY_NAME,
                    fileName
                )

                put(
                    MediaStore.Images.Media.MIME_TYPE,
                    "image/jpeg"
                )

                if (
                    Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.Q
                ) {

                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES +
                            "/CDAC Assistant"
                    )

                    put(
                        MediaStore.Images.Media.IS_PENDING,
                        1
                    )
                }
            }


        val uri =
            contentResolver.insert(
                MediaStore.Images.Media
                    .EXTERNAL_CONTENT_URI,
                values
            ) ?: throw IllegalStateException(
                "Unable to create image in MediaStore"
            )


        try {

            contentResolver
                .openOutputStream(
                    uri
                )
                ?.use { stream ->

                    stream.write(
                        bytes
                    )

                    stream.flush()

                } ?: throw IllegalStateException(
                    "Unable to open image output stream"
                )


            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.Q
            ) {

                val ready =
                    ContentValues().apply {

                        put(
                            MediaStore.Images.Media.IS_PENDING,
                            0
                        )
                    }

                contentResolver.update(
                    uri,
                    ready,
                    null,
                    null
                )
            }

        } catch (
            e: Exception
        ) {

            try {
                contentResolver.delete(
                    uri,
                    null,
                    null
                )
            } catch (_: Exception) {
            }

            throw e
        }


        return fileName
    }


    private fun jpegOrientation(
        characteristics: CameraCharacteristics,
        frontCamera: Boolean
    ): Int {

        @Suppress("DEPRECATION")
        val rotation =
            windowManager
                .defaultDisplay
                .rotation


        val deviceDegrees =
            when (rotation) {

                Surface.ROTATION_90 ->
                    90

                Surface.ROTATION_180 ->
                    180

                Surface.ROTATION_270 ->
                    270

                else ->
                    0
            }


        val sensorOrientation =
            characteristics.get(
                CameraCharacteristics
                    .SENSOR_ORIENTATION
            ) ?: 0


        return if (frontCamera) {

            (
                sensorOrientation +
                deviceDegrees
            ) % 360

        } else {

            (
                sensorOrientation -
                deviceDegrees +
                360
            ) % 360
        }
    }


    @Suppress("MissingPermission")
    private fun capturePhoto(
        frontCamera: Boolean,
        result: MethodChannel.Result
    ) {

        val completed =
            AtomicBoolean(
                false
            )

        val cameraManager =
            getSystemService(
                Context.CAMERA_SERVICE
            ) as CameraManager


        val requestedFacing =
            if (frontCamera) {

                CameraCharacteristics
                    .LENS_FACING_FRONT

            } else {

                CameraCharacteristics
                    .LENS_FACING_BACK
            }


        val cameraId =
            cameraManager
                .cameraIdList
                .firstOrNull { id ->

                    cameraManager
                        .getCameraCharacteristics(
                            id
                        )
                        .get(
                            CameraCharacteristics
                                .LENS_FACING
                        ) ==
                        requestedFacing
                }


        if (
            cameraId == null
        ) {

            result.error(
                "CAMERA_NOT_FOUND",
                if (frontCamera) {
                    "Front camera was not found."
                } else {
                    "Back camera was not found."
                },
                null
            )

            return
        }


        val characteristics =
            cameraManager
                .getCameraCharacteristics(
                    cameraId
                )


        val configurationMap =
            characteristics.get(
                CameraCharacteristics
                    .SCALER_STREAM_CONFIGURATION_MAP
            )


        val jpegSizes =
            configurationMap
                ?.getOutputSizes(
                    ImageFormat.JPEG
                )
                ?.toList()
                ?: emptyList()


        if (
            jpegSizes.isEmpty()
        ) {

            result.error(
                "CAMERA_CAPTURE_UNSUPPORTED",
                "This camera does not expose JPEG capture sizes.",
                null
            )

            return
        }


        /*
         * Prefer a good-quality image without
         * unnecessarily selecting a huge sensor size.
         */

        val preferredSizes =
            jpegSizes.filter {
                (
                    it.width.toLong() *
                    it.height.toLong()
                ) <= 12_000_000L
            }


        val size =
            (
                if (
                    preferredSizes.isNotEmpty()
                ) {
                    preferredSizes
                } else {
                    jpegSizes
                }
            ).maxByOrNull {
                it.width.toLong() *
                it.height.toLong()
            } ?: jpegSizes.first()


        val imageReader =
            ImageReader.newInstance(
                size.width,
                size.height,
                ImageFormat.JPEG,
                1
            )


        val cameraThread =
            HandlerThread(
                "CDAC-Camera-Capture"
            ).apply {
                start()
            }


        val cameraHandler =
            Handler(
                cameraThread.looper
            )


        var cameraDevice:
            CameraDevice? = null

        var captureSession:
            CameraCaptureSession? = null


        fun cleanup() {

            try {
                captureSession
                    ?.close()
            } catch (_: Exception) {
            }

            try {
                cameraDevice
                    ?.close()
            } catch (_: Exception) {
            }

            try {
                imageReader.close()
            } catch (_: Exception) {
            }

            try {
                cameraThread
                    .quitSafely()
            } catch (_: Exception) {
            }
        }


        fun finishError(
            message: String
        ) {

            if (
                !completed.compareAndSet(
                    false,
                    true
                )
            ) {
                return
            }

            runOnUiThread {

                result.error(
                    "CAMERA_CAPTURE_FAILED",
                    message,
                    null
                )
            }
        }


        fun finishSuccess(
            fileName: String
        ) {

            if (
                !completed.compareAndSet(
                    false,
                    true
                )
            ) {
                return
            }

            val lens =
                if (frontCamera) {
                    "Front"
                } else {
                    "Back"
                }

            runOnUiThread {

                result.success(
                    "$lens photo saved: $fileName"
                )
            }
        }


        imageReader
            .setOnImageAvailableListener(
                { reader ->

                    val image =
                        reader.acquireLatestImage()
                            ?: return@setOnImageAvailableListener

                    try {

                        val buffer =
                            image
                                .planes[0]
                                .buffer

                        val bytes =
                            ByteArray(
                                buffer.remaining()
                            )

                        buffer.get(
                            bytes
                        )


                        val fileName =
                            saveCapturedPhoto(
                                bytes,
                                frontCamera
                            )


                        finishSuccess(
                            fileName
                        )

                    } catch (
                        e: Exception
                    ) {

                        finishError(
                            e.message
                                ?: e.javaClass.simpleName
                        )

                    } finally {

                        try {
                            image.close()
                        } catch (_: Exception) {
                        }

                        cleanup()
                    }
                },
                cameraHandler
            )


        try {

            cameraManager.openCamera(
                cameraId,

                object :
                    CameraDevice.StateCallback() {

                    override fun onOpened(
                        camera: CameraDevice
                    ) {

                        cameraDevice =
                            camera


                        try {

                            camera
                                .createCaptureSession(
                                    listOf(
                                        imageReader.surface
                                    ),

                                    object :
                                        CameraCaptureSession
                                            .StateCallback() {

                                        override fun onConfigured(
                                            session:
                                                CameraCaptureSession
                                        ) {

                                            captureSession =
                                                session


                                            try {

                                                val request =
                                                    camera
                                                        .createCaptureRequest(
                                                            CameraDevice
                                                                .TEMPLATE_STILL_CAPTURE
                                                        )
                                                        .apply {

                                                            addTarget(
                                                                imageReader
                                                                    .surface
                                                            )

                                                            set(
                                                                CaptureRequest
                                                                    .JPEG_ORIENTATION,

                                                                jpegOrientation(
                                                                    characteristics,
                                                                    frontCamera
                                                                )
                                                            )
                                                        }


                                                session.capture(
                                                    request.build(),

                                                    object :
                                                        CameraCaptureSession
                                                            .CaptureCallback() {

                                                        override fun onCaptureFailed(
                                                            session:
                                                                CameraCaptureSession,
                                                            request:
                                                                CaptureRequest,
                                                            failure:
                                                                CaptureFailure
                                                        ) {

                                                            finishError(
                                                                "Camera capture failed."
                                                            )

                                                            cleanup()
                                                        }
                                                    },

                                                    cameraHandler
                                                )

                                            } catch (
                                                e: Exception
                                            ) {

                                                finishError(
                                                    e.message
                                                        ?: e.javaClass.simpleName
                                                )

                                                cleanup()
                                            }
                                        }


                                        override fun onConfigureFailed(
                                            session:
                                                CameraCaptureSession
                                        ) {

                                            finishError(
                                                "Unable to configure camera capture."
                                            )

                                            cleanup()
                                        }
                                    },

                                    cameraHandler
                                )

                        } catch (
                            e: Exception
                        ) {

                            finishError(
                                e.message
                                    ?: e.javaClass.simpleName
                            )

                            cleanup()
                        }
                    }


                    override fun onDisconnected(
                        camera: CameraDevice
                    ) {

                        finishError(
                            "Camera disconnected."
                        )

                        cleanup()
                    }


                    override fun onError(
                        camera: CameraDevice,
                        error: Int
                    ) {

                        finishError(
                            "Camera error code: $error"
                        )

                        cleanup()
                    }
                },

                cameraHandler
            )

        } catch (
            e: Exception
        ) {

            finishError(
                e.message
                    ?: e.javaClass.simpleName
            )

            cleanup()
        }
    }


    private data class ContactMatch(
        val displayName: String,
        val phoneNumber: String
    )


    private fun handleWhatsApp(
        requestedContact: String,
        message: String,
        result: MethodChannel.Result
    ) {

        if (
            requestedContact.isBlank() ||
            message.isBlank()
        ) {

            result.error(
                "WHATSAPP_BAD_REQUEST",
                "Contact and message are required.",
                null
            )

            return
        }


        /*
         * Android runtime contact permission.
         */

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.M &&
            checkSelfPermission(
                Manifest.permission.READ_CONTACTS
            ) !=
            PackageManager.PERMISSION_GRANTED
        ) {

            pendingWhatsAppContact =
                requestedContact

            pendingWhatsAppMessage =
                message

            pendingWhatsAppResult =
                result

            requestPermissions(
                arrayOf(
                    Manifest.permission.READ_CONTACTS
                ),
                CONTACTS_PERMISSION_REQUEST
            )

            return
        }


        performWhatsApp(
            requestedContact,
            message,
            result
        )
    }


    private fun normalizeContactName(
        value: String
    ): String {

        return value
            .lowercase()
            .replace(
                Regex(
                    "[^\\p{L}\\p{N}]+"
                ),
                " "
            )
            .trim()
    }


    private fun findContactPhone(
        requestedContact: String
    ): ContactMatch? {

        val requested =
            normalizeContactName(
                requestedContact
            )

        if (requested.isBlank()) {
            return null
        }


        val projection =
            arrayOf(
                ContactsContract
                    .CommonDataKinds
                    .Phone
                    .DISPLAY_NAME,

                ContactsContract
                    .CommonDataKinds
                    .Phone
                    .NUMBER,

                ContactsContract
                    .CommonDataKinds
                    .Phone
                    .NORMALIZED_NUMBER
            )


        var bestMatch:
            ContactMatch? = null

        var bestScore =
            0


        contentResolver.query(
            ContactsContract
                .CommonDataKinds
                .Phone
                .CONTENT_URI,
            projection,
            null,
            null,
            null
        )?.use { cursor ->

            val nameIndex =
                cursor.getColumnIndex(
                    ContactsContract
                        .CommonDataKinds
                        .Phone
                        .DISPLAY_NAME
                )

            val numberIndex =
                cursor.getColumnIndex(
                    ContactsContract
                        .CommonDataKinds
                        .Phone
                        .NUMBER
                )

            val normalizedIndex =
                cursor.getColumnIndex(
                    ContactsContract
                        .CommonDataKinds
                        .Phone
                        .NORMALIZED_NUMBER
                )


            while (
                cursor.moveToNext()
            ) {

                if (
                    nameIndex < 0 ||
                    numberIndex < 0
                ) {
                    continue
                }


                val displayName =
                    cursor.getString(
                        nameIndex
                    ) ?: continue


                val rawNumber =
                    cursor.getString(
                        numberIndex
                    ) ?: continue


                val normalizedNumber =
                    if (
                        normalizedIndex >= 0
                    ) {
                        cursor.getString(
                            normalizedIndex
                        )
                    } else {
                        null
                    }


                val candidateName =
                    normalizeContactName(
                        displayName
                    )


                val score =
                    when {

                        candidateName ==
                        requested -> {
                            100
                        }

                        candidateName
                            .startsWith(
                                "$requested "
                            ) -> {
                            90
                        }

                        candidateName
                            .contains(
                                requested
                            ) -> {
                            70
                        }

                        requested
                            .contains(
                                candidateName
                            ) -> {
                            50
                        }

                        else -> {
                            0
                        }
                    }


                if (
                    score >
                    bestScore
                ) {

                    bestScore =
                        score

                    bestMatch =
                        ContactMatch(
                            displayName =
                                displayName,

                            phoneNumber =
                                normalizedNumber
                                    ?.takeIf {
                                        it.isNotBlank()
                                    }
                                    ?: rawNumber
                        )
                }
            }
        }


        return bestMatch
    }


    private fun normalizeWhatsAppNumber(
        rawNumber: String
    ): String {

        var digits =
            rawNumber
                .replace(
                    Regex("[^0-9]"),
                    ""
                )


        /*
         * Remove international dial-out prefix.
         *
         * Example:
         * 0091... -> 91...
         */

        if (
            digits.startsWith(
                "00"
            )
        ) {

            digits =
                digits.substring(2)
        }


        /*
         * Demo fallback for Indian 10-digit
         * mobile numbers when the Contacts
         * provider does not expose an E.164
         * normalized number.
         *
         * 9876543210
         * becomes
         * 919876543210
         */

        if (
            digits.length ==
            10
        ) {

            digits =
                "91$digits"
        }


        return digits
    }


    private fun performWhatsApp(
        requestedContact: String,
        message: String,
        result: MethodChannel.Result
    ) {

        try {

            val contact =
                findContactPhone(
                    requestedContact
                )


            if (
                contact == null
            ) {

                result.success(
                    "Contact not found: " +
                    requestedContact
                )

                return
            }


            val phone =
                normalizeWhatsAppNumber(
                    contact.phoneNumber
                )


            if (
                phone.length < 8
            ) {

                result.success(
                    "No valid phone number found for " +
                    contact.displayName
                )

                return
            }


            /*
             * WhatsApp opens the selected chat
             * with the message pre-filled.
             *
             * The user performs the final Send tap.
             */

            val whatsappUri =
                Uri.parse(
                    "https://wa.me/" +
                    phone +
                    "?text=" +
                    Uri.encode(
                        message
                    )
                )


            fun openPackage(
                packageName: String
            ): Boolean {

                return try {

                    val intent =
                        Intent(
                            Intent.ACTION_VIEW,
                            whatsappUri
                        ).apply {

                            setPackage(
                                packageName
                            )

                            addFlags(
                                Intent
                                    .FLAG_ACTIVITY_CLEAR_TOP
                            )
                        }


                    startActivity(
                        intent
                    )

                    true

                } catch (
                    _: ActivityNotFoundException
                ) {

                    false

                } catch (
                    _: Exception
                ) {

                    false
                }
            }


            /*
             * Normal WhatsApp.
             */

            var opened =
                openPackage(
                    "com.whatsapp"
                )


            /*
             * WhatsApp Business fallback.
             */

            if (!opened) {

                opened =
                    openPackage(
                        "com.whatsapp.w4b"
                    )
            }


            if (!opened) {

                result.error(
                    "WHATSAPP_NOT_FOUND",
                    "WhatsApp is not installed or cannot open this chat.",
                    null
                )

                return
            }


            result.success(
                "Opened WhatsApp for " +
                contact.displayName +
                " with message ready: " +
                message
            )

        } catch (
            e: Exception
        ) {

            result.error(
                "WHATSAPP_FAILED",
                e.message
                    ?: e.javaClass.simpleName,
                null
            )
        }
    }


    private fun handleFlashlight(
        enabled: Boolean,
        result: MethodChannel.Result
    ) {
        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.M
        ) {
            result.error(
                "TORCH_UNSUPPORTED",
                "Flashlight control requires Android 6 or newer.",
                null
            )

            return
        }

        /*
         * Request camera permission if this OEM
         * requires it for direct torch access.
         */
        if (
            checkSelfPermission(
                Manifest.permission.CAMERA
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingTorchEnabled = enabled
            pendingTorchResult = result

            requestPermissions(
                arrayOf(
                    Manifest.permission.CAMERA
                ),
                CAMERA_PERMISSION_REQUEST
            )

            return
        }

        performFlashlight(
            enabled,
            result
        )
    }


    private fun performFlashlight(
        enabled: Boolean,
        result: MethodChannel.Result
    ) {
        try {
            val cameraManager =
                getSystemService(
                    Context.CAMERA_SERVICE
                ) as CameraManager

            /*
             * Prefer rear camera + flash.
             */
            val rearFlashCamera =
                cameraManager.cameraIdList
                    .firstOrNull { cameraId ->

                        val info =
                            cameraManager
                                .getCameraCharacteristics(
                                    cameraId
                                )

                        val hasFlash =
                            info.get(
                                CameraCharacteristics
                                    .FLASH_INFO_AVAILABLE
                            ) == true

                        val facing =
                            info.get(
                                CameraCharacteristics
                                    .LENS_FACING
                            )

                        hasFlash &&
                            facing ==
                            CameraCharacteristics
                                .LENS_FACING_BACK
                    }

            /*
             * If an unusual phone exposes flash
             * differently, use any camera with flash.
             */
            val fallbackFlashCamera =
                cameraManager.cameraIdList
                    .firstOrNull { cameraId ->

                        val info =
                            cameraManager
                                .getCameraCharacteristics(
                                    cameraId
                                )

                        info.get(
                            CameraCharacteristics
                                .FLASH_INFO_AVAILABLE
                        ) == true
                    }

            val cameraId =
                rearFlashCamera
                    ?: fallbackFlashCamera
                    ?: throw IllegalStateException(
                        "This device has no controllable flashlight."
                    )

            cameraManager.setTorchMode(
                cameraId,
                enabled
            )

            result.success(
                if (enabled) {
                    "Flashlight turned on"
                } else {
                    "Flashlight turned off"
                }
            )

        } catch (e: Exception) {
            result.error(
                "TORCH_FAILED",
                e.message ?: e.javaClass.simpleName,
                null
            )
        }
    }


    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {

        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )


        /*
         * Flashlight permission.
         */

        if (
            requestCode ==
            CAMERA_PERMISSION_REQUEST
        ) {

            val result =
                pendingTorchResult

            pendingTorchResult =
                null


            if (
                grantResults.isNotEmpty() &&
                grantResults[0] ==
                PackageManager
                    .PERMISSION_GRANTED
            ) {

                if (
                    result != null
                ) {

                    performFlashlight(
                        pendingTorchEnabled,
                        result
                    )
                }

            } else {

                result?.error(
                    "CAMERA_PERMISSION_DENIED",
                    "Camera permission is required for flashlight control.",
                    null
                )
            }

            return
        }


        /*
         * Local music permission.
         */

        if (
            requestCode ==
            AUDIO_PERMISSION_REQUEST
        ) {

            val result =
                pendingMusicResult

            val query =
                pendingMusicQuery


            pendingMusicResult =
                null

            pendingMusicQuery =
                ""


            if (
                grantResults.isNotEmpty() &&
                grantResults[0] ==
                PackageManager
                    .PERMISSION_GRANTED
            ) {

                if (
                    result != null
                ) {

                    performLocalMusicPlayback(
                        query,
                        result
                    )
                }

            } else {

                result?.error(
                    "AUDIO_PERMISSION_DENIED",
                    "Music and audio permission is required for local playback.",
                    null
                )
            }

            return
        }
    

        /*
         * Direct front/back photo capture permission.
         */

        if (
            requestCode ==
            CAMERA_CAPTURE_PERMISSION_REQUEST
        ) {

            val result =
                pendingPhotoCaptureResult

            val front =
                pendingPhotoCaptureFront


            pendingPhotoCaptureResult =
                null


            if (
                grantResults.isNotEmpty() &&
                grantResults[0] ==
                PackageManager
                    .PERMISSION_GRANTED
            ) {

                if (
                    result != null
                ) {

                    capturePhoto(
                        front,
                        result
                    )
                }

            } else {

                result?.error(
                    "CAMERA_PERMISSION_DENIED",
                    "Camera permission is required to take a photo.",
                    null
                )
            }

            return
        }


        /*
         * WhatsApp contact permission.
         */

        if (
            requestCode ==
            CONTACTS_PERMISSION_REQUEST
        ) {

            val result =
                pendingWhatsAppResult

            val contact =
                pendingWhatsAppContact

            val message =
                pendingWhatsAppMessage


            pendingWhatsAppResult =
                null

            pendingWhatsAppContact =
                ""

            pendingWhatsAppMessage =
                ""


            if (
                grantResults.isNotEmpty() &&
                grantResults[0] ==
                PackageManager
                    .PERMISSION_GRANTED
            ) {

                if (
                    result != null
                ) {

                    performWhatsApp(
                        contact,
                        message,
                        result
                    )
                }

            } else {

                result?.error(
                    "CONTACT_PERMISSION_DENIED",
                    "Contacts permission is required to find the WhatsApp recipient.",
                    null
                )
            }

            return
        }

}


    override fun onDestroy() {

        try {
            localMediaPlayer
                ?.release()
        } catch (_: Exception) {
        }

        localMediaPlayer =
            null

        super.onDestroy()
    }

}
