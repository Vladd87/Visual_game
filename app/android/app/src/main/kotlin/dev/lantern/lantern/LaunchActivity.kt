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
    companion object {
        /** Set by a finished auto-test run: start the next one. */
        const val EXTRA_AUTO_NEXT = "lantern.auto_next"

        /**
         * The automatic test series: each setup [AUTO_ROUNDS] times,
         * interleaved. Each run takes the title screen apart piece by piece
         * and reads the screen back (device bring-up).
         */
        private val AUTO_MODES: List<Pair<String, List<String>>> = listOf(
            "default" to emptyList<String>(),
        )
        private const val AUTO_ROUNDS = 3
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra(EXTRA_AUTO_NEXT, false) == true && advanceAuto()) return
        // Final release: no test menu, straight into the game.
        if (!bringupMenu()) {
            startGame(emptyList(), steps = false, auto = null)
            return
        }
        showMenu(CrashReport.build(this))
    }

    private fun bringupMenu(): Boolean = try {
        @Suppress("DEPRECATION")
        val info = packageManager.getApplicationInfo(packageName, android.content.pm.PackageManager.GET_META_DATA)
        info.metaData?.getString("dev.lantern.bringup")?.let { it != "false" }
            ?: info.metaData?.getBoolean("dev.lantern.bringup", true) ?: true
    } catch (_: Throwable) { true }

    private fun autoFile() = File(filesDir, "auto.txt")

    /** Starts auto-test run [index], or ends the series; true if a run was started. */
    private fun startAuto(index: Int): Boolean {
        val total = AUTO_MODES.size * AUTO_ROUNDS
        if (index >= total) {
            autoFile().delete()
            CrashReport.recordRun(this, "=== auto test finished ($total runs)")
            return false
        }
        autoFile().writeText("$index\n")
        val (_, flags) = AUTO_MODES[index % AUTO_MODES.size]
        startGame(flags, steps = true, auto = "${index + 1}/$total")
        return true
    }

    private fun advanceAuto(): Boolean {
        val i = try { autoFile().readText().trim().toInt() } catch (_: Throwable) { return false }
        return startAuto(i + 1)
    }

    /**
     * [mode]: null, or one of MainActivity's EXTRA_* diagnostic flags.
     * [steps]: step-by-step bring-up run (bright banner, screen read-back).
     */
    private fun startGame(mode: String?, steps: Boolean = true) =
        startGame(listOfNotNull(mode), steps, null)

    private fun startGame(flags: List<String>, steps: Boolean, auto: String?) {
        CrashReport.killGameProcesses(this)
        CrashReport.clearStep(this)
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (steps) intent.putExtra(MainActivity.EXTRA_STEP_BY_STEP, true)
        for (f in flags) {
            // "key=n" is an int extra, a bare key a boolean flag.
            val eq = f.indexOf('=')
            if (eq > 0) intent.putExtra(f.substring(0, eq), f.substring(eq + 1).toInt()) else intent.putExtra(f, true)
        }
        if (auto != null) intent.putExtra(MainActivity.EXTRA_AUTO, auto)
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
            text = "Play starts the game. Auto test runs 3 short launches by itself (about 1 minute): just watch, don't touch, and when this menu comes back, tap Copy and paste the report. Each run shows a yellow banner with its number."
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
            text = "Play"
            setOnClickListener { startGame(null, steps = false) }
        })
        row1.addView(Button(this).apply {
            text = "Clear runs"
            textSize = 11f
            setOnClickListener {
                CrashReport.clearRuns(this@LaunchActivity)
                showMenu(CrashReport.build(this@LaunchActivity))
            }
        })
        root.addView(row1)
        val row2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row2.addView(Button(this).apply {
            text = "Auto test"
            textSize = 12f
            setOnClickListener {
                CrashReport.recordRun(this@LaunchActivity, "=== auto test started")
                startAuto(0)
            }
        })
        for ((label, flag) in listOf(
            "Texture view" to MainActivity.EXTRA_TEXTURE_VIEW,
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

    private fun runsFile(ctx: Context) = File(ctx.filesDir, "runs.txt")

    /** Appends one line to the history of test runs (kept across launches). */
    fun recordRun(ctx: Context, line: String) {
        try {
            val stamp = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
            val f = runsFile(ctx)
            val old = if (f.exists()) f.readLines().takeLast(150) else emptyList()
            f.writeText((old + "$stamp $line").joinToString("\n") + "\n")
        } catch (_: Throwable) {
        }
    }

    fun clearRuns(ctx: Context) {
        try {
            runsFile(ctx).delete()
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
        val runs = try { runsFile(ctx).readLines() } catch (_: Throwable) { emptyList() }
        if (runs.isNotEmpty()) {
            sb.append("\n--- test runs (screen read-back at each step: window = Android window, surface/texture = Flutter) ---\n")
            sb.append(runs.joinToString("\n")).append('\n')
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
