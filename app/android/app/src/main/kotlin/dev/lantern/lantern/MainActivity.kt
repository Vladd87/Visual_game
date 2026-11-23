package dev.lantern.lantern

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
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
        /** Diagnostic modes picked on [LaunchActivity]'s report screen. */
        const val EXTRA_PLAIN_MATERIALS = "lantern.plain_materials"
        const val EXTRA_NO_EFFECTS = "lantern.no_effects"
        const val EXTRA_NO_3D = "lantern.no_3d"
        const val EXTRA_NO_SCENE = "lantern.no_scene"
        const val EXTRA_STEP_BY_STEP = "lantern.step_by_step"
        /** Flutter renders into a TextureView drawn by Android's own renderer. */
        const val EXTRA_TEXTURE_VIEW = "lantern.texture_view"
        /** Bring-up: hold each loading step and read the screen back at it. */
        const val EXTRA_SLOW_STEPS = "lantern.slow_steps"
        /** Bring-up: part of the launcher's automatic test series ("run k/n"). */
        const val EXTRA_AUTO = "lantern.auto"
        /** Bring-up: water material variant (0 = the real one). */
        const val EXTRA_WATER_VARIANT = "lantern.water_variant"
    }

    private fun flag(name: String) = intent?.getBooleanExtra(name, false) == true

    // Flutter's default surface (an opaque SurfaceView below the window).
    // Test builds 6-8 tried a translucent surface on top and a TextureView;
    // neither mattered: the black screen was a layout bug (game_page.dart).
    // The texture view stays as a bring-up option.
    override fun getRenderMode(): RenderMode =
        if (flag(EXTRA_TEXTURE_VIEW)) RenderMode.texture else RenderMode.surface

    // Lazy, not lateinit: FlutterActivity calls configureFlutterEngine() from
    // inside super.onCreate(), which registers these as channel handlers. With
    // lateinit they were still unset there and every launch crashed ~130 ms
    // after start (UninitializedPropertyAccessException). The activity is
    // already attached at that point, so creating them on first use is safe.
    private val displayMode by lazy { DisplayModeHelper(this) }
    private val thermal by lazy { ThermalHelper(this) }
    private val haptics by lazy { HapticsHelper(this) }
    private val tilt by lazy { TiltHelper(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.attributes = window.attributes.apply {
            layoutInDisplayCutoutMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else {
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        enterImmersive()
        // Auto test: a run that never finishes its checks still hands over.
        if (intent?.getStringExtra(EXTRA_AUTO) != null) {
            Handler(Looper.getMainLooper()).postDelayed({
                CrashReport.recordRun(this, "RUN ${intent?.getStringExtra(EXTRA_AUTO)}: timed out after 45 s")
                nextRun()
            }, 45_000)
        }
    }

    private var handedOver = false

    /** Auto test: back to the launcher, which kills this process and starts the next run. */
    private fun nextRun() {
        if (handedOver) return
        handedOver = true
        val i = Intent(this, LaunchActivity::class.java)
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        i.putExtra(LaunchActivity.EXTRA_AUTO_NEXT, true)
        startActivity(i)
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
                    "plainMaterials" to intent.getBooleanExtra(EXTRA_PLAIN_MATERIALS, false),
                    "noEffects" to intent.getBooleanExtra(EXTRA_NO_EFFECTS, false),
                    "no3d" to intent.getBooleanExtra(EXTRA_NO_3D, false),
                    "noScene" to flag(EXTRA_NO_SCENE),
                    "stepByStep" to flag(EXTRA_STEP_BY_STEP),
                    "textureView" to flag(EXTRA_TEXTURE_VIEW),
                    "slowSteps" to flag(EXTRA_SLOW_STEPS),
                    "auto" to (intent?.getStringExtra(EXTRA_AUTO) != null)))
                "autoLabel" -> result.success(intent?.getStringExtra(EXTRA_AUTO))
                "waterVariant" -> result.success(intent?.getIntExtra(EXTRA_WATER_VARIANT, 0) ?: 0)
                "nextRun" -> {
                    nextRun()
                    result.success(null)
                }
                "screenProbe" -> {
                    val step = call.argument<String>("step") ?: "?"
                    ScreenProbe.run(this, step, step == "title screen 1") { line -> result.success(line) }
                }
                "recordRun" -> {
                    CrashReport.recordRun(this, call.argument<String>("line") ?: "")
                    result.success(null)
                }
                "bootStep" -> {
                    CrashReport.recordStep(this, call.argument<String>("step") ?: "?")
                    result.success(null)
                }
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
