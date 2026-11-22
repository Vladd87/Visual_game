package dev.lantern.lantern

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import io.flutter.plugin.common.EventChannel
import kotlin.math.abs

/**
 * Locks the panel to one refresh mode so an LTPO display does not hunt
 * between rates (the source of judder at "60 fps"). The request is per
 * display, so it is re-applied whenever the active display changes, which on a
 * foldable happens on every fold/unfold.
 */
class DisplayModeHelper(private val activity: Activity) : DisplayManager.DisplayListener, EventChannel.StreamHandler {
    private val displayManager = activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private val main = Handler(Looper.getMainLooper())
    private var targetHz = 60f
    private var sink: EventChannel.EventSink? = null

    init {
        displayManager.registerDisplayListener(this, main)
    }

    @Suppress("DEPRECATION")
    private fun currentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display else activity.windowManager.defaultDisplay

    /** Requests [hz] (60 or 120); returns the refresh rate actually selected. */
    fun request(hz: Float): Double {
        targetHz = hz
        return reapply()
    }

    fun reapply(): Double {
        val display = currentDisplay() ?: return 0.0
        val current = display.mode
        val candidates = display.supportedModes.filter {
            it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight
        }.ifEmpty { display.supportedModes.toList() }
        val best = candidates.minByOrNull { abs(it.refreshRate - targetHz) } ?: return 0.0
        val lp = activity.window.attributes
        if (lp.preferredDisplayModeId != best.modeId || lp.preferredRefreshRate != best.refreshRate) {
            lp.preferredDisplayModeId = best.modeId
            lp.preferredRefreshRate = best.refreshRate
            activity.window.attributes = lp
        }
        return best.refreshRate.toDouble()
    }

    fun info(): Map<String, Any> {
        val display = currentDisplay() ?: return emptyMap()
        val mode = display.mode
        return mapOf(
            "displayId" to display.displayId,
            "name" to (display.name ?: ""),
            "widthPx" to mode.physicalWidth,
            "heightPx" to mode.physicalHeight,
            "refreshRate" to display.refreshRate.toDouble(),
            "targetHz" to targetHz.toDouble(),
            "modes" to display.supportedModes.map { "${it.physicalWidth}x${it.physicalHeight}@${"%.0f".format(it.refreshRate)}" },
            "hdr" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) display.isHdr else false),
            "wideColor" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) display.isWideColorGamut else false),
        )
    }

    override fun onDisplayAdded(displayId: Int) {}
    override fun onDisplayRemoved(displayId: Int) {}
    override fun onDisplayChanged(displayId: Int) {
        if (displayId == currentDisplay()?.displayId) {
            reapply()
            sink?.success(info())
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        events?.success(info())
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun dispose() {
        displayManager.unregisterDisplayListener(this)
    }
}
