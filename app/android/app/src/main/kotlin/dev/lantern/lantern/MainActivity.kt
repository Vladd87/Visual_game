package dev.lantern.lantern

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * LANTERN host activity.
 *
 * The activity is never recreated on fold/unfold (see configChanges in the
 * manifest), so the Flutter GPU context and every scene resource survive a
 * screen switch. Native helpers cover what Flutter does not: a fixed display
 * refresh mode, thermal status/headroom, amplitude haptics and a
 * screen-oriented tilt vector.
 */
class MainActivity : FlutterActivity() {
    companion object {
        /** Set by [LaunchActivity] when the player picks "Safe mode". */
        const val EXTRA_SAFE_MODE = "lantern.safe_mode"
    }

    private lateinit var displayMode: DisplayModeHelper
    private lateinit var thermal: ThermalHelper
    private lateinit var haptics: HapticsHelper
    private lateinit var tilt: TiltHelper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        displayMode = DisplayModeHelper(this)
        thermal = ThermalHelper(this)
        haptics = HapticsHelper(this)
        tilt = TiltHelper(this)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.attributes = window.attributes.apply {
            layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        enterImmersive()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "lantern/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "setRefreshRate" -> {
                    val hz = (call.argument<Double>("hz") ?: 60.0).toFloat()
                    result.success(displayMode.request(hz))
                }
                "displayInfo" -> result.success(displayMode.info())
                "launchFlags" -> result.success(mapOf(
                    "safeMode" to intent.getBooleanExtra(EXTRA_SAFE_MODE, false)))
                "haptic" -> {
                    haptics.pulse((call.argument<Double>("strength") ?: 0.5).toFloat())
                    result.success(null)
                }
                "thermal" -> result.success(thermal.snapshot())
                "perfLogDir" -> result.success(getExternalFilesDir(null)?.absolutePath)
                "immersive" -> {
                    enterImmersive()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "lantern/thermal").setStreamHandler(thermal)
        EventChannel(messenger, "lantern/tilt").setStreamHandler(tilt)
        EventChannel(messenger, "lantern/display").setStreamHandler(displayMode)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enterImmersive()
            displayMode.reapply()
        }
    }

    override fun onResume() {
        super.onResume()
        displayMode.reapply()
        tilt.resume()
    }

    override fun onPause() {
        tilt.pause()
        super.onPause()
    }

    override fun onDestroy() {
        thermal.dispose()
        displayMode.dispose()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun enterImmersive() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.systemBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        }
    }
}
