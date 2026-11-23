package dev.lantern.lantern

import android.app.Activity
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup

/**
 * Device bring-up: reads back what the phone actually shows.
 *
 * Two layers make up the screen: Flutter's own surface (a SurfaceView, or a
 * TextureView in texture mode) and the Android window around it. The window
 * normally leaves a transparent hole over the SurfaceView. Copying both tells
 * apart "Flutter presents black frames" (surface dark) from "Flutter's frames
 * are fine but something opaque covers them" (surface bright, window opaque
 * and dark over it).
 */
object ScreenProbe {
    private const val TAG = "LANTERN"
    private const val W = 54
    private const val H = 126

    fun run(activity: Activity, step: String, dumpTree: Boolean, done: (String) -> Unit) {
        val views = ArrayList<View>()
        collect(activity.window.decorView, views)
        if (dumpTree) {
            for ((i, v) in views.withIndex()) Log.i(TAG, "LANTERN_VIEW $i ${describe(v)}")
        }
        val sv = views.filterIsInstance<SurfaceView>().firstOrNull()
        val tv = views.filterIsInstance<TextureView>().firstOrNull()
        val main = Handler(Looper.getMainLooper())
        val parts = ArrayList<String>()
        fun finish() {
            val line = parts.joinToString(" ")
            Log.i(TAG, "LANTERN_PIX $step $line")
            done(line)
        }
        fun copyFlutter() {
            when {
                sv != null && sv.holder.surface?.isValid == true -> {
                    val b = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
                    try {
                        PixelCopy.request(sv, b, { r ->
                            parts.add("surface=" + stats(b, r))
                            finish()
                        }, main)
                    } catch (t: Throwable) {
                        parts.add("surface=EXC(${t.javaClass.simpleName})")
                        finish()
                    }
                }
                tv != null -> {
                    val b = try { tv.getBitmap(W, H) } catch (_: Throwable) { null }
                    parts.add("texture=" + (if (b == null) "null" else stats(b, PixelCopy.SUCCESS)))
                    finish()
                }
                else -> {
                    parts.add(if (sv != null) "surface=invalid" else "no-flutter-view")
                    finish()
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val wb = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
            try {
                PixelCopy.request(activity.window, wb, { r ->
                    parts.add("window=" + stats(wb, r))
                    copyFlutter()
                }, main)
            } catch (t: Throwable) {
                parts.add("window=EXC(${t.javaClass.simpleName})")
                copyFlutter()
            }
        } else {
            copyFlutter()
        }
    }

    private fun collect(v: View, out: MutableList<View>) {
        out.add(v)
        if (v is ViewGroup) for (i in 0 until v.childCount) collect(v.getChildAt(i), out)
    }

    private fun describe(v: View): String {
        val vis = when (v.visibility) { View.VISIBLE -> "V"; View.INVISIBLE -> "I"; else -> "G" }
        val bg = v.background?.javaClass?.simpleName ?: "-"
        return "${v.javaClass.simpleName} $vis a=${v.alpha} ${v.width}x${v.height} z=${v.z} bg=$bg"
    }

    /** "L=<mean luma 0-255> A=<mean alpha> lit=<% pixels with luma > 8>", or the copy error. */
    private fun stats(b: Bitmap, result: Int): String {
        if (result != PixelCopy.SUCCESS) return "ERR$result"
        val px = IntArray(b.width * b.height)
        b.getPixels(px, 0, b.width, 0, 0, b.width, b.height)
        var sumL = 0L
        var sumA = 0L
        var lit = 0
        for (c in px) {
            val a = (c ushr 24) and 0xff
            val r = (c shr 16) and 0xff
            val g = (c shr 8) and 0xff
            val bl = c and 0xff
            val l = (r * 2 + g * 5 + bl) shr 3
            sumL += l
            sumA += a
            if (l > 8) lit++
        }
        val n = px.size
        return "L=${"%.1f".format(sumL.toDouble() / n)} A=${sumA / n} lit=${100 * lit / n}%"
    }
}
