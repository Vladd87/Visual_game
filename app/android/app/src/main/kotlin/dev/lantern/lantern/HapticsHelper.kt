package dev.lantern.lantern

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Light collision haptics with strength. Prefers the crisp composition
 * primitives (a soft "tick" for light bumps, a "click" for hard knocks), and
 * falls back to a short amplitude-scaled one-shot.
 */
class HapticsHelper(activity: Activity) {
    @Suppress("DEPRECATION")
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    } else {
        activity.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }

    fun pulse(strength: Float) {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        val s = strength.coerceIn(0f, 1f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val primitive = if (s < 0.45f) VibrationEffect.Composition.PRIMITIVE_TICK else VibrationEffect.Composition.PRIMITIVE_CLICK
            if (v.areAllPrimitivesSupported(primitive)) {
                v.vibrate(
                    VibrationEffect.startComposition()
                        .addPrimitive(primitive, 0.25f + 0.75f * s)
                        .compose()
                )
                return
            }
        }
        val amp = (40 + 200 * s).toInt().coerceIn(1, 255)
        v.vibrate(VibrationEffect.createOneShot((10 + 18 * s).toLong(), if (v.hasAmplitudeControl()) amp else VibrationEffect.DEFAULT_AMPLITUDE))
    }
}
