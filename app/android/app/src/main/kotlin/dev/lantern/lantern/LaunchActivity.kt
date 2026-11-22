package dev.lantern.lantern

import android.app.Activity
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Launcher activity: plain Android views, no Flutter, so it still works when
 * the game's renderer is what crashes.
 *
 * Normally it just starts [MainActivity]. If the previous launch ended in a
 * crash (Android's own exit record, API 30+), it first shows a report built
 * from that record (reason, description, native crash strings) and from the
 * app's own log lines of the crashed process, with a Copy button so the
 * text can be pasted straight into a message. Each crash is shown once.
 */
class LaunchActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val report = CrashReport.pending(this)
        if (report == null) {
            startGame(null)
            return
        }
        showReport(report)
    }

    /** [mode]: null, or one of MainActivity's EXTRA_* diagnostic flags. */
    private fun startGame(mode: String?) {
        val intent = Intent(this, MainActivity::class.java)
        if (mode != null) intent.putExtra(mode, true)
        startActivity(intent)
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    private fun showReport(report: String) {
        val pad = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(12, 14, 18))
            setPadding(pad, pad * 2, pad, pad)
        }
        root.addView(TextView(this).apply {
            text = if (report.startsWith("STALL")) "Lantern did not finish starting last time" else "Lantern stopped last time"
            setTextColor(Color.rgb(255, 200, 150))
            textSize = 20f
        })
        root.addView(TextView(this).apply {
            text = "Tap Copy and paste the report into your message to the developer."
            setTextColor(Color.rgb(200, 200, 200))
            textSize = 14f
            setPadding(0, pad / 2, 0, pad / 2)
        })
        val body = TextView(this).apply {
            text = report
            setTextColor(Color.rgb(220, 220, 220))
            typeface = Typeface.MONOSPACE
            textSize = 10f
            setTextIsSelectable(true)
        }
        root.addView(ScrollView(this).apply { addView(body) }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        buttons.addView(Button(this).apply {
            text = "Copy"
            setOnClickListener {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("Lantern crash report", report))
                Toast.makeText(this@LaunchActivity, "Report copied", Toast.LENGTH_SHORT).show()
            }
        })
        buttons.addView(Button(this).apply {
            text = "Start"
            setOnClickListener { startGame(null) }
        })
        root.addView(buttons)
        root.addView(TextView(this).apply {
            text = "Test modes (to find what fails):"
            setTextColor(Color.rgb(170, 170, 170))
            textSize = 12f
            setPadding(0, pad / 2, 0, 0)
        })
        val modes = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for ((label, flag) in listOf(
            "Plain materials" to MainActivity.EXTRA_PLAIN_MATERIALS,
            "No effects" to MainActivity.EXTRA_NO_EFFECTS,
            "No 3D" to MainActivity.EXTRA_NO_3D,
        )) {
            modes.addView(Button(this).apply {
                text = label
                textSize = 12f
                setOnClickListener { startGame(flag) }
            })
        }
        root.addView(modes)
        setContentView(root)
    }
}

object CrashReport {
    private const val PREFS = "lantern_crash_report"

    /**
     * Records the game's current boot step (called from Dart). commit(), not
     * apply(): it must be on disk if the process is killed right after.
     */
    fun recordStep(ctx: Context, step: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("step", step)
            .putInt("stepPid", android.os.Process.myPid())
            .commit()
    }

    /**
     * The report for the most recent exit not shown yet: an abnormal exit
     * (crash, ANR, ...) or, whatever the exit reason, a launch whose boot
     * never reached "ready" (a hang the player swiped away). Null otherwise.
     */
    fun pending(ctx: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = ctx.getSystemService(ActivityManager::class.java) ?: return null
            val last = am.getHistoricalProcessExitReasons(ctx.packageName, 0, 1).firstOrNull() ?: return null
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (last.timestamp <= prefs.getLong("seen", 0L)) return null
            prefs.edit().putLong("seen", last.timestamp).apply()
            val step = prefs.getString("step", null)
            val stalled = step != null && step != "ready" && prefs.getInt("stepPid", -1) == last.pid
            when {
                last.reason in abnormal -> build(ctx, last, step)
                stalled -> "STALL: the game stopped at boot step \"$step\" and was closed.\n" + build(ctx, last, step)
                else -> null
            }
        } catch (t: Throwable) {
            null
        }
    }

    private val abnormal = setOf(
        ApplicationExitInfo.REASON_CRASH,
        ApplicationExitInfo.REASON_CRASH_NATIVE,
        ApplicationExitInfo.REASON_ANR,
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE,
        ApplicationExitInfo.REASON_SIGNALED,
        ApplicationExitInfo.REASON_UNKNOWN,
        ApplicationExitInfo.REASON_LOW_MEMORY,
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
        ApplicationExitInfo.REASON_DEPENDENCY_DIED,
    )

    private fun reasonName(r: Int): String = when (r) {
        ApplicationExitInfo.REASON_CRASH -> "CRASH (Java/Kotlin exception)"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE (native code)"
        ApplicationExitInfo.REASON_ANR -> "ANR (not responding)"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED (closed)"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED (force stop)"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        else -> "reason $r"
    }

    private fun build(ctx: Context, e: ApplicationExitInfo, step: String?): String {
        val sb = StringBuilder()
        val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(e.timestamp))
        val version = try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName
        } catch (t: Throwable) { "?" }
        sb.append("Lantern $version  ·  ${Build.MANUFACTURER} ${Build.MODEL}  ·  Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})\n")
        sb.append("Exit: ${reasonName(e.reason)}  status=${e.status}  at $time\n")
        e.description?.let { sb.append("Description: $it\n") }
        if (step != null) sb.append("Last boot step: $step\n")
        sb.append("Memory at exit: pss=${e.pss / 1024} MB rss=${e.rss / 1024} MB\n")
        // Native crashes (API 31+) carry the tombstone; ANRs carry text traces.
        try {
            e.traceInputStream?.use { input ->
                val bytes = input.readBytes()
                sb.append("\n--- trace (${bytes.size} bytes) ---\n")
                if (e.reason == ApplicationExitInfo.REASON_ANR) {
                    sb.append(String(bytes).lineSequence().take(60).joinToString("\n"))
                } else {
                    sb.append(printableStrings(bytes).take(80).joinToString("\n"))
                }
                sb.append('\n')
            }
        } catch (t: Throwable) {
            sb.append("(trace unavailable: ${t.javaClass.simpleName})\n")
        }
        sb.append("\n--- log of the crashed process (pid ${e.pid}) ---\n")
        sb.append(ownLog(e.pid))
        return sb.toString()
    }

    /** Readable text runs in a binary tombstone (abort message, frames). */
    private fun printableStrings(bytes: ByteArray): List<String> {
        val out = LinkedHashSet<String>()
        val cur = StringBuilder()
        for (b in bytes) {
            val c = b.toInt() and 0xff
            if (c in 32..126) {
                cur.append(c.toChar())
            } else {
                if (cur.length >= 6) out.add(cur.toString())
                cur.setLength(0)
            }
        }
        if (cur.length >= 6) out.add(cur.toString())
        return out.toList()
    }

    /**
     * The app may read its own log lines (same UID), including those of the
     * process that just died, while they are still in the log buffer.
     */
    private fun ownLog(pid: Int): String {
        return try {
            val p = ProcessBuilder("logcat", "-d", "-v", "time", "-t", "4000").redirectErrorStream(true).start()
            val lines = p.inputStream.bufferedReader().readLines()
            p.waitFor()
            // "-v time" pads the pid: "E/AndroidRuntime(  577): ...".
            val tag = Regex("\\(\\s*$pid\\)")
            val mine = lines.filter { tag.containsMatchIn(it) || it.contains(" $pid ") }
            val keep = mine.filter { l ->
                !l.contains(" V/") && !l.contains(" D/") || l.contains("flutter", true) || l.contains("impeller", true)
            }
            (if (keep.isEmpty()) lines.takeLast(80) else keep.takeLast(220)).joinToString("\n")
        } catch (t: Throwable) {
            "(log unavailable: ${t.javaClass.simpleName}: ${t.message})"
        }
    }
}
