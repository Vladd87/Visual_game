package dev.lantern.lantern

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel

/**
 * Thermal status (API 29) and thermal headroom forecast (API 30) for the
 * quality governor. Streams a snapshot every 2 s and on every status change.
 */
class ThermalHelper(activity: Activity) : EventChannel.StreamHandler {
    private val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val statusListener = PowerManager.OnThermalStatusChangedListener { sink?.success(snapshot()) }
    private val poll = object : Runnable {
        override fun run() {
            sink?.success(snapshot())
            main.postDelayed(this, 2000)
        }
    }

    fun snapshot(): Map<String, Any> {
        val headroom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            power.getThermalHeadroom(10).toDouble() // forecast 10 s ahead; 1.0 = throttling
        } else {
            Double.NaN
        }
        return mapOf(
            "status" to power.currentThermalStatus,
            "headroom" to (if (headroom.isNaN()) -1.0 else headroom),
            "powerSave" to power.isPowerSaveMode,
        )
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        power.addThermalStatusListener(statusListener)
        main.post(poll)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        power.removeThermalStatusListener(statusListener)
        main.removeCallbacks(poll)
    }

    fun dispose() {
        onCancel(null)
    }
}
