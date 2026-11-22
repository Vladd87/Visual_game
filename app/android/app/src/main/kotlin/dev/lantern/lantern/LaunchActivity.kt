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
import android.os.Process
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Launcher: plain Android views in its own process (":launcher"), so it keeps
 * working while the game's renderer is crashed or hung.
 *
 * While the game is being brought up on new hardware it is a small test
 * menu: it shows how the last game process ended (Android's exit record),
 * the boot step it reached, and that process's own log lines, with a Copy
 * button; and it starts the game normally or in one of three diagnostic
 * modes. Before starting, it kills any game process still running (a hung
 * renderer otherwise just comes back to the front).
 */
class LaunchActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showMenu(CrashReport.build(this))
    }

    /** [mode]: null, or one of MainActivity's EXTRA_* diagnostic flags. */
    private fun startGame(mode: String?) {
        CrashReport.killGameProcesses(this)
        CrashReport.clearStep(this)
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (mode != null) intent.putExtra(mode, true)
        startActivity(intent)
        finish()
    }

    private fun showMenu(report: String) {
        val pad = (14 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(12, 14, 18))
            setPadding(pad, pad * 2, pad, pad)
        }
        root.addView(TextView(this).apply {
            text = "Lantern test build"
            setTextColor(Color.rgb(255, 200, 150))
            textSize = 20f
        })
        root.addView(TextView(this).apply {
            text = "If the game shows a black screen, close it, open Lantern again, tap Copy and paste the text to the developer. Then try the test modes and say which ones show something."
            setTextColor(Color.rgb(200, 200, 200))
            textSize = 13f
            setPadding(0, pad / 2, 0, pad / 2)
        })
        val body = TextView(this).apply {
            text = report
            setTextColor(Color.rgb(220, 220, 220))
            typeface = Typeface.MONOSPACE
            textSize = 9f
            setTextIsSelectable(true)
        }
        root.addView(ScrollView(this).apply { addView(body) }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        val row1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row1.addView(Button(this).apply {
            text = "Copy"
            setOnClickListener {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("Lantern report", report))
                Toast.makeText(this@LaunchActivity, "Report copied", Toast.LENGTH_SHORT).show()
            }
        })
        row1.addView(Button(this).apply {
            text = "Start game"
            setOnClickListener { startGame(null) }
        })
        root.addView(row1)
        val row2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        for ((label, flag) in listOf(
            "Plain materials" to MainActivity.EXTRA_PLAIN_MATERIALS,
            "No effects" to MainActivity.EXTRA_NO_EFFECTS,
            "No 3D" to MainActivity.EXTRA_NO_3D,
        )) {
            row2.addView(Button(this).apply {
                text = label
                textSize = 12f
                setOnClickListener { startGame(flag) }
            })
        }
        root.addView(row2)
        setContentView(root)
    }
}

object CrashReport {
    // A file, not SharedPreferences: the launcher runs in another process and
    // a SharedPreferences cache there would be stale.
    private fun stepFile(ctx: Context) = File(ctx.filesDir, "boot_step.txt")

    /** Records the game's current boot step (called from Dart via MainActivity). */
    fun recordStep(ctx: Context, step: String) {
        try {
            val stamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date())
            stepFile(ctx).writeText("$step\n${Process.myPid()}\n$stamp\n")
        } catch (_: Throwable) {
        }
    }

    fun clearStep(ctx: Context) {
        try {
            stepFile(ctx).delete()
        } catch (_: Throwable) {
        }
    }

    /** Kills every process of this app except the launcher's own. */
    fun killGameProcesses(ctx: Context) {
        try {
            val am = ctx.getSystemService(ActivityManager::class.java) ?: return
            for (p in am.runningAppProcesses ?: emptyList()) {
                if (p.pid != Process.myPid() && p.uid == Process.myUid()) Process.killProcess(p.pid)
            }
        } catch (_: Throwable) {
        }
    }

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
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        else -> "reason $r"
    }

    /** Everything known about the last game run. */
    fun build(ctx: Context): String {
        val sb = StringBuilder()
        val version = try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName
        } catch (_: Throwable) { "?" }
        sb.append("Lantern $version (${ctx.packageName})  ·  ${Build.MANUFACTURER} ${Build.MODEL}  ·  Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})\n")
        val lines = try { stepFile(ctx).readLines() } catch (_: Throwable) { emptyList() }
        val step = lines.getOrNull(0)
        val pid = lines.getOrNull(1)?.toIntOrNull()
        if (step == null) {
            sb.append("No record of a previous game run.\n")
        } else {
            sb.append("Last game run: pid $pid reached boot step \"$step\" at ${lines.getOrNull(2)}\n")
        }
        val running = try {
            ctx.getSystemService(ActivityManager::class.java)?.runningAppProcesses
                ?.filter { it.pid != Process.myPid() }?.map { "${it.processName} (pid ${it.pid})" }
        } catch (_: Throwable) { null }
        if (!running.isNullOrEmpty()) sb.append("Still running: ${running.joinToString()}\n")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val am = ctx.getSystemService(ActivityManager::class.java)
                val exits = am?.getHistoricalProcessExitReasons(ctx.packageName, 0, 3) ?: emptyList()
                for (e in exits) {
                    val time = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(e.timestamp))
                    sb.append("Exit at $time: pid ${e.pid} ${e.processName}: ${reasonName(e.reason)}")
                    e.description?.let { sb.append(" ($it)") }
                    sb.append('\n')
                    if (e.pid == pid && e.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                        try {
                            e.traceInputStream?.use { input ->
                                sb.append("--- native crash strings ---\n")
                                sb.append(printableStrings(input.readBytes()).take(60).joinToString("\n")).append('\n')
                            }
                        } catch (_: Throwable) {
                        }
                    }
                }
            } catch (_: Throwable) {
            }
        }
        sb.append("\n--- log of the last game run")
        sb.append(if (pid != null) " (pid $pid) ---\n" else " ---\n")
        sb.append(ownLog(pid))
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
     * The app may read its own log lines (same UID), including those of a
     * game process that died or is still hung.
     */
    private fun ownLog(pid: Int?): String {
        return try {
            val p = ProcessBuilder("logcat", "-d", "-v", "time", "-t", "6000").redirectErrorStream(true).start()
            val lines = p.inputStream.bufferedReader().readLines()
            p.waitFor()
            val mine = if (pid == null) lines else {
                // "-v time" pads the pid: "E/AndroidRuntime(  577): ...".
                val tag = Regex("\\(\\s*$pid\\)")
                lines.filter { tag.containsMatchIn(it) || it.contains(" $pid ") }
            }
            val keep = mine.filter { l ->
                (!l.contains(" V/") && !l.contains(" D/")) || l.contains("flutter", true) || l.contains("impeller", true)
            }
            (if (keep.isEmpty()) mine.takeLast(60) else keep.takeLast(250)).joinToString("\n")
        } catch (t: Throwable) {
            "(log unavailable: ${t.javaClass.simpleName}: ${t.message})"
        }
    }
}
