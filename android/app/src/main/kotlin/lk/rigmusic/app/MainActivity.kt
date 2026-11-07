package lk.rigmusic.app

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/// Live microphone capture for the tuner.
///
/// Exposes one [EventChannel] (`rigmusic/mic_stream`) to Dart:
///   * first event  -> `mapOf("sampleRate" to <actual rate>)` so the pitch
///     maths always uses the rate the device really records at;
///   * then raw PCM16 little-endian mono bytes as they are captured;
///   * errors (permission denied / no mic) arrive as channel errors.
///
/// Uses the platform's [AudioRecord] directly — no third-party plugins —
/// and requests RECORD_AUDIO at runtime when Dart first listens.
class MainActivity : FlutterActivity() {

    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null

    @Volatile
    private var capturing = false
    private var permissionInFlight = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startWhenPermitted()
                }

                override fun onCancel(arguments: Any?) {
                    stopCapture()
                    eventSink = null
                }
            })
    }

    private fun startWhenPermitted() {
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        if (granted) {
            startCapture()
        } else if (!permissionInFlight) {
            permissionInFlight = true
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                MIC_PERMISSION_REQUEST
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == MIC_PERMISSION_REQUEST) {
            permissionInFlight = false
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            when {
                !granted -> postError("mic_permission", "Microphone permission was denied.")
                // The user may have tapped Stop while the dialog was up —
                // only start if Dart is still listening to the channel.
                eventSink != null -> startCapture()
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun startCapture() {
        if (capturing || eventSink == null) return

        val rate = pickSampleRate()
        if (rate == null) {
            postError("mic_unsupported", "This device cannot record 16-bit mono audio.")
            return
        }

        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuffer = AudioRecord.getMinBufferSize(rate, channelConfig, audioFormat)
        if (minBuffer <= 0) {
            postError("mic_unsupported", "This device cannot record 16-bit mono audio.")
            return
        }
        val bufferSize = maxOf(minBuffer * 2, 8192)

        val recorder = try {
            AudioRecord(MediaRecorder.AudioSource.MIC, rate, channelConfig, audioFormat, bufferSize)
        } catch (e: SecurityException) {
            postError("mic_permission", "Microphone permission was denied.")
            return
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            postError("mic_unavailable", "Could not open the microphone.")
            return
        }

        audioRecord = recorder
        recorder.startRecording()
        capturing = true

        // Announce the real rate before any audio so Dart's Hz maths is exact.
        postEvent(hashMapOf<String, Any>("sampleRate" to rate))

        captureThread = Thread {
            val buffer = ByteArray(bufferSize)
            while (capturing) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read > 0) {
                    val chunk = buffer.copyOf(read)
                    mainHandler.post {
                        if (capturing) eventSink?.success(chunk)
                    }
                } else if (read < 0) {
                    break
                }
            }
        }.apply {
            name = "rigmusic-mic-capture"
            isDaemon = true
            start()
        }
    }

    /// 48 kHz first (near-universal), 44.1 kHz as the fallback.
    private fun pickSampleRate(): Int? {
        for (rate in intArrayOf(48000, 44100)) {
            val min = AudioRecord.getMinBufferSize(
                rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            if (min > 0) return rate
        }
        return null
    }

    private fun stopCapture() {
        capturing = false
        captureThread?.join(750)
        captureThread = null
        audioRecord?.let { recorder ->
            try {
                recorder.stop()
            } catch (_: IllegalStateException) {
                // Never started / already stopped — nothing to do.
            }
            recorder.release()
        }
        audioRecord = null
    }

    private fun postEvent(event: Any) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun postError(code: String, message: String) {
        mainHandler.post { eventSink?.error(code, message, null) }
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_NAME = "rigmusic/mic_stream"
        private const val MIC_PERMISSION_REQUEST = 4412
    }
}
