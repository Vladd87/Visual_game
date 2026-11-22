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
            startGame(safe = false)
            return
        }
        showReport(report)
    }

    private fun startGame(safe: Boolean) {
        val intent = Intent(this, MainActivity::class.java)
        intent.putExtra(MainActivity.EXTRA_SAFE_MODE, safe)
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
            text = "Lantern stopped last time"
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
            text = "Safe mode"
            setOnClickListener { startGame(safe = true) }
        })
        buttons.addView(Button(this).apply {
            text = "Start"
            setOnClickListener { startGame(safe = false) }
        })
        root.addView(buttons)
        setContentView(root)
    }
}

object CrashReport {
    private const val PREFS = "lantern_crash_report"

    /** The report for the most recent abnormal exit not shown yet, or null. */
    fun pending(ctx: Context): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = ctx.getSystemService(ActivityManager::class.java) ?: return null
            val last = am.getHistoricalProcessExitReasons(ctx.packageName, 0, 1).firstOrNull() ?: return null
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (last.timestamp <= prefs.getLong("seen", 0L)) return null
            prefs.edit().putLong("seen", last.timestamp).apply()
            if (last.reason !in abnormal) return null
            build(ctx, last)
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
        else -> "reason $r"
    }

    private fun build(ctx: Context, e: ApplicationExitInfo): String {
        val sb = StringBuilder()
        val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(e.timestamp))
        val version = try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName
        } catch (t: Throwable) { "?" }
        sb.append("Lantern $version  ·  ${Build.MANUFACTURER} ${Build.MODEL}  ·  Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})\n")
        sb.append("Exit: ${reasonName(e.reason)}  status=${e.status}  at $time\n")
        e.description?.let { sb.append("Description: $it\n") }
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
            val tag = "($pid)"
            val mine = lines.filter { it.contains(tag) || it.contains(" $pid ") }
            val keep = mine.filter { l ->
                !l.contains(" V/") && !l.contains(" D/") || l.contains("flutter", true) || l.contains("impeller", true)
            }
            (if (keep.isEmpty()) lines.takeLast(80) else keep.takeLast(150)).joinToString("\n")
        } catch (t: Throwable) {
            "(log unavailable: ${t.javaClass.simpleName}: ${t.message})"
        }
    }
}
