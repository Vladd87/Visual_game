package dev.lantern.lantern

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.view.Surface
import io.flutter.plugin.common.EventChannel

/**
 * Gravity in *screen* coordinates (x right, y down, z out of the screen),
 * normalised to g. The remap uses the current display rotation, so the
 * vector is correct on the cover screen, the inner screen and in any
 * orientation; Dart subtracts a neutral pose captured at run start (and on
 * every posture change) to turn it into a tilt nudge.
 */
class TiltHelper(private val activity: Activity) : SensorEventListener, EventChannel.StreamHandler {
    private val sensors = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val gravity: Sensor? = sensors.getDefaultSensor(Sensor.TYPE_GRAVITY)
        ?: sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var sink: EventChannel.EventSink? = null
    private var listening = false
    private var lastSent = 0L

    @Suppress("DEPRECATION")
    private fun rotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display?.rotation ?: Surface.ROTATION_0
        else activity.windowManager.defaultDisplay.rotation

    override fun onSensorChanged(event: SensorEvent) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastSent < 14) return // ~70 Hz is plenty for a nudge
        lastSent = now
        // Device axes: x right, y up (natural orientation), z out of screen.
        // The sensor reports the reaction to gravity (points up when still).
        val ax = event.values[0]
        val ay = event.values[1]
        val az = event.values[2]
        // Remap to the current screen orientation (x right, y up).
        val (sx, sy) = when (rotation()) {
            Surface.ROTATION_90 -> Pair(-ay, ax)
            Surface.ROTATION_180 -> Pair(-ax, -ay)
            Surface.ROTATION_270 -> Pair(ay, -ax)
            else -> Pair(ax, ay)
        }
        // "Downhill" in screen space (x right, y down): opposite of the reaction vector.
        val g = SensorManager.GRAVITY_EARTH
        sink?.success(doubleArrayOf((-sx / g).toDouble(), (sy / g).toDouble(), (az / g).toDouble()))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        resume()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        pause()
    }

    fun resume() {
        if (sink != null && !listening && gravity != null) {
            sensors.registerListener(this, gravity, SensorManager.SENSOR_DELAY_GAME)
            listening = true
        }
    }

    fun pause() {
        if (listening) {
            sensors.unregisterListener(this)
            listening = false
        }
    }
}
