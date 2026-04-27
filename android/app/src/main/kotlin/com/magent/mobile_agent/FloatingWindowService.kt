package com.magent.mobile_agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.text.TextUtils
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.noties.markwon.Markwon
import io.noties.markwon.ext.tables.TablePlugin
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * Fully-native floating overlay — no Flutter Engine involved.
 *
 * Layout (top → bottom):
 *   ┌──────────────────────────────────────┐
 *   │  ● Session title              [✕]   │  ← header / drag zone
 *   ├──────────────────────────────────────┤
 *   │  ⬤ Running…  (status row)           │
 *   ├──────────────────────────────────────┤
 *   │  Last assistant message text         │
 *   │  (up to 7 lines, truncated)          │
 *   ├──────────────────────────────────────┤
 *   │        Tap to open Mag  ›            │
 *   └──────────────────────────────────────┘
 *
 * Data is fetched from the local HTTP server and updated via SSE.
 */
class FloatingWindowService : Service() {

    companion object {
        const val ACTION_SHOW = "com.magent.mobile_agent.floating.SHOW"
        const val ACTION_HIDE = "com.magent.mobile_agent.floating.HIDE"

        private const val TAG = "MagFloat"          // logcat filter: tag:MagFloat
        private const val NOTIF_CHANNEL_ID = "floating_agent"
        private const val NOTIF_ID = 4307

        const val EXTRA_SERVER_URI = "serverUri"
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_SESSION_TITLE = "sessionTitle"
        const val EXTRA_WORKSPACE_ID = "workspaceId"
        const val EXTRA_WORKSPACE_NAME = "workspaceName"
        const val EXTRA_WORKSPACE_DIRECTORY = "workspaceDirectory"
        const val EXTRA_DARK_MODE = "darkMode"
    }

    // ── Config ────────────────────────────────────────────────────────────────
    private var serverUri = ""
    private var sessionId = ""
    private var sessionTitle = ""
    private var workspaceId = ""
    private var darkMode = false

    // ── Display mode ──────────────────────────────────────────────────────────
    private enum class DisplayMode { MINI, LINE, FULL }
    private var displayMode = DisplayMode.FULL

    // ── Window ────────────────────────────────────────────────────────────────
    private lateinit var windowManager: WindowManager
    private var container: FloatingContainer? = null
    private var wParams: WindowManager.LayoutParams? = null

    // Mode view roots
    private var miniView: View? = null
    private var lineView: View? = null
    private var fullView: View? = null

    // MINI-mode labels
    private var miniDot: View? = null
    private var miniLabel: TextView? = null

    // LINE-mode labels
    private var lineDot: View? = null
    private var lineStatusTv: TextView? = null
    private var lineMsgTv: TextView? = null

    // FULL-mode refs (existing)
    private var dotView: View? = null
    private var statusLabel: TextView? = null
    private var messageLabel: TextView? = null
    private var msgScrollView: ScrollView? = null

    private var markwon: Markwon? = null
    private var autoScroll = true
    private var lastMsgText = ""

    // ── Background work ───────────────────────────────────────────────────────
    private val io = Executors.newCachedThreadPool()
    private val ui = Handler(Looper.getMainLooper())

    @Volatile private var sseActive = false
    private var sseThread: Thread? = null
    @Volatile private var sseConn: HttpURLConnection? = null

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        when (intent.action) {
            ACTION_HIDE -> { stopSelf(); return START_NOT_STICKY }
            ACTION_SHOW -> {
                serverUri    = intent.getStringExtra(EXTRA_SERVER_URI)    ?: ""
                sessionId    = intent.getStringExtra(EXTRA_SESSION_ID)    ?: ""
                sessionTitle = intent.getStringExtra(EXTRA_SESSION_TITLE) ?: ""
                workspaceId  = intent.getStringExtra(EXTRA_WORKSPACE_ID)  ?: ""
                darkMode     = intent.getBooleanExtra(EXTRA_DARK_MODE, false)
                Log.d(TAG, "ACTION_SHOW  serverUri=$serverUri  sessionId=$sessionId  workspaceId=$workspaceId")
                tearDown()
                startForegroundCompat()
                buildWindow()
                loadData()
                connectSse()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        tearDown()
        io.shutdownNow()
        super.onDestroy()
    }

    // ── Build overlay window ──────────────────────────────────────────────────

    private fun buildWindow() {
        markwon  = Markwon.builder(this)
            .usePlugin(TablePlugin.create(this))
            .build()
        autoScroll = true

        val dm  = resources.displayMetrics
        val dp  = dm.density
        val sw  = dm.widthPixels
        val fullW = (sw * 0.72f).roundToInt()
        val miniW = WRAP_CONTENT                      // pill auto-sizes

        // ── Colour palette ────────────────────────────────────────────────────
        val bg       = if (darkMode) Color.parseColor("#1C1C1E") else Color.WHITE
        val divClr   = if (darkMode) Color.parseColor("#3A3A3C") else Color.parseColor("#E5E5EA")
        val txPri    = if (darkMode) Color.parseColor("#EBEBF5") else Color.parseColor("#1C1C1E")
        val txSec    = if (darkMode) Color.parseColor("#8E8E93") else Color.parseColor("#6C6C70")
        val border   = if (darkMode) Color.parseColor("#3A3A3C") else Color.parseColor("#D1D1D6")
        val accent   = Color.parseColor("#007AFF")

        fun dotBg(color: Int = Color.parseColor("#30D158")) =
            GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(color) }

        fun pill(radius: Float = 16f * dp) = GradientDrawable().apply {
            shape         = GradientDrawable.RECTANGLE
            cornerRadius  = radius
            setColor(bg)
            setStroke((1f * dp).roundToInt(), border)
        }

        fun divider() = View(this).apply {
            setBackgroundColor(divClr)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, 1)
        }

        val hPad   = (12f * dp).roundToInt()
        val sPadV  = (8f  * dp).roundToInt()
        val mPad   = (12f * dp).roundToInt()
        val iconPad = (8f * dp).roundToInt()
        val dotSz  = (8f  * dp).roundToInt()

        // ── Container (rounded rect, draggable) ───────────────────────────────
        val c = FloatingContainer()
        c.background = pill()
        container    = c

        // ═══════════════════════════════════════════════════════════════════════
        //  MINI mode  — compact status chip  "● Running…  [⊞]"
        // ═══════════════════════════════════════════════════════════════════════
        val mDot = View(this).apply {
            background   = dotBg()
            layoutParams = LinearLayout.LayoutParams(dotSz, dotSz).apply { marginEnd = (6f*dp).roundToInt() }
        }
        miniDot = mDot

        val mLabel = TextView(this).apply {
            text     = "加载中…"
            setTextColor(txPri)
            textSize = 12f
            maxLines  = 1
            ellipsize = TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
        }
        miniLabel = mLabel

        val mExpand = TextView(this).apply {
            text     = "⊞"
            setTextColor(txSec)
            textSize = 14f
            setPadding(iconPad, iconPad, iconPad, iconPad)
            setOnClickListener { setMode(DisplayMode.FULL) }
        }
        c.addExtraNoInterceptRef(mExpand)

        val mv = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER_VERTICAL
            setPadding(hPad, sPadV, (6f*dp).roundToInt(), sPadV)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setOnClickListener { setMode(DisplayMode.FULL) }
            addView(mDot)
            addView(mLabel)
            addView(mExpand)
        }
        miniView = mv

        // ═══════════════════════════════════════════════════════════════════════
        //  LINE mode  — one-line bar  "● Running… | First line of message…  [⊞]"
        // ═══════════════════════════════════════════════════════════════════════
        val lDot = View(this).apply {
            background   = dotBg()
            layoutParams = LinearLayout.LayoutParams(dotSz, dotSz).apply { marginEnd = (6f*dp).roundToInt() }
        }
        lineDot = lDot

        val lStatus = TextView(this).apply {
            text      = "加载中…"
            setTextColor(txSec)
            textSize  = 12f
            maxLines   = 1
            layoutParams = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginEnd = (8f*dp).roundToInt()
            }
        }
        lineStatusTv = lStatus

        val lSep = View(this).apply {
            setBackgroundColor(divClr)
            layoutParams = LinearLayout.LayoutParams((1f*dp).roundToInt(), (16f*dp).roundToInt()).apply {
                marginEnd = (8f*dp).roundToInt()
            }
        }

        val lMsg = TextView(this).apply {
            text     = ""
            setTextColor(txPri)
            textSize = 12f
            maxLines  = 1
            ellipsize = TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
        }
        lineMsgTv = lMsg

        val lExpand = TextView(this).apply {
            text     = "⊞"
            setTextColor(txSec)
            textSize = 14f
            setPadding(iconPad, iconPad, iconPad, iconPad)
            setOnClickListener { setMode(DisplayMode.FULL) }
        }
        c.addExtraNoInterceptRef(lExpand)

        val lv = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity     = Gravity.CENTER_VERTICAL
            setPadding(hPad, sPadV, (6f*dp).roundToInt(), sPadV)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setOnClickListener { setMode(DisplayMode.FULL) }
            addView(lDot)
            addView(lStatus)
            addView(lSep)
            addView(lMsg)
            addView(lExpand)
        }
        lineView = lv

        // ═══════════════════════════════════════════════════════════════════════
        //  FULL mode  — expanded view with header, scroll area, footer
        // ═══════════════════════════════════════════════════════════════════════

        // Header row (drag zone)
        val headerH = (44f * dp).roundToInt()
        val header  = LinearLayout(this).apply {
            orientation  = LinearLayout.HORIZONTAL
            gravity      = Gravity.CENTER_VERTICAL
            setPadding(hPad, 0, (6f*dp).roundToInt(), 0)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, headerH)
        }

        val dot = View(this).apply {
            background   = dotBg()
            layoutParams = LinearLayout.LayoutParams(dotSz, dotSz).apply { marginEnd = (6f*dp).roundToInt() }
        }
        dotView = dot

        val title = TextView(this).apply {
            text     = sessionTitle.ifEmpty { "Mag" }
            setTextColor(txPri)
            textSize = 13f
            setTypeface(null, Typeface.BOLD)
            maxLines  = 1
            ellipsize = TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
        }

        // "─" collapses to MINI
        val collapseBtn = TextView(this).apply {
            text     = "─"
            setTextColor(txSec)
            textSize = 16f
            setPadding(iconPad, iconPad, iconPad, iconPad)
            setOnClickListener { setMode(DisplayMode.MINI) }
        }
        c.addExtraNoInterceptRef(collapseBtn)

        val closeBtn = TextView(this).apply {
            text     = "✕"
            setTextColor(txSec)
            textSize = 14f
            setPadding(iconPad, iconPad, iconPad, iconPad)
            setOnClickListener { ui.post { stopSelf() } }
        }
        c.closeBtnRef = closeBtn

        header.addView(dot)
        header.addView(title)
        header.addView(collapseBtn)
        header.addView(closeBtn)

        // Status row
        val status = TextView(this).apply {
            text     = "加载中…"
            setTextColor(txSec)
            textSize = 11f
            maxLines  = 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(hPad, sPadV, hPad, sPadV)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        statusLabel = status

        // Message scroll area
        val scrollH = (172f * dp).roundToInt()

        val msg = TextView(this).apply {
            text     = ""
            setTextColor(txPri)
            textSize = 13f
            setPadding(mPad, mPad, mPad, mPad)
            setLineSpacing(3f * dp, 1f)
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
        messageLabel = msg

        val sv = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams   = FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            addView(msg)
        }
        msgScrollView = sv

        // Detect manual scroll to disable auto-scroll
        sv.viewTreeObserver.addOnScrollChangedListener {
            val child = sv.getChildAt(0) ?: return@addOnScrollChangedListener
            val maxScroll = (child.height - sv.height).coerceAtLeast(0)
            autoScroll = sv.scrollY >= maxScroll - 16
        }

        // ↓ scroll-to-bottom button (only shown when user has scrolled up)
        val btnSz  = (26f * dp).roundToInt()
        val btnMar = (6f  * dp).roundToInt()
        val downBtn = TextView(this).apply {
            text     = "↓"
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity  = Gravity.CENTER
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(accent) }
            layoutParams = FrameLayout.LayoutParams(btnSz, btnSz).apply {
                gravity      = Gravity.BOTTOM or Gravity.END
                bottomMargin = btnMar
                marginEnd    = btnMar
            }
            setOnClickListener {
                autoScroll = true
                sv.post { sv.fullScroll(View.FOCUS_DOWN) }
            }
        }

        val msgArea = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, scrollH)
            addView(sv)
            addView(downBtn)
        }

        // Footer
        val footer = TextView(this).apply {
            text     = l("打开 Mag  ›", "Open Mag  ›")
            setTextColor(accent)
            textSize = 11f
            gravity  = Gravity.CENTER
            setPadding(mPad, sPadV, mPad, sPadV)
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setOnClickListener { openMainApp() }
        }

        val fv = LinearLayout(this).apply {
            orientation  = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            addView(header)
            addView(divider())
            addView(status)
            addView(divider())
            addView(msgArea)
            addView(divider())
            addView(footer)
        }
        fullView = fv

        // ── Root: stacks the three mode views, only one visible at a time ─────
        val root = LinearLayout(this).apply {
            orientation  = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            addView(mv)
            addView(lv)
            addView(fv)
        }
        c.addView(root)

        // ── WindowManager params ──────────────────────────────────────────────
        val overlayType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val lp = WindowManager.LayoutParams(
            fullW, WRAP_CONTENT, overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).also {
            it.gravity = Gravity.TOP or Gravity.START
            it.x = (sw - fullW) / 2
            it.y = (dm.heightPixels * 0.12f).roundToInt()
        }
        wParams = lp
        c.wm    = windowManager
        c.lp    = lp
        windowManager.addView(c, lp)

        // Apply initial mode (shows FULL, hides MINI & LINE)
        setMode(displayMode)
    }

    /**
     * Switch display mode; adjusts window width and shows/hides mode views.
     * Must be called on the UI thread.
     */
    private fun setMode(mode: DisplayMode) {
        displayMode = mode
        val dm    = resources.displayMetrics
        val dp    = dm.density
        val fullW = (dm.widthPixels * 0.72f).roundToInt()

        miniView?.visibility = if (mode == DisplayMode.MINI) View.VISIBLE else View.GONE
        lineView?.visibility = if (mode == DisplayMode.LINE) View.VISIBLE else View.GONE
        fullView?.visibility = if (mode == DisplayMode.FULL) View.VISIBLE else View.GONE

        val newW = if (mode == DisplayMode.MINI) WRAP_CONTENT else fullW
        wParams?.let { p ->
            if (p.width != newW) {
                p.width = newW
                container?.let { runCatching { windowManager.updateViewLayout(it, p) } }
            }
        }
    }

    /** Simple l10n helper (no context needed here). */
    private fun l(zh: String, en: String) = zh   // device locale not wired; keep Chinese

    // ── Data loading ──────────────────────────────────────────────────────────

    /** Fetch current status and last message.  Retries up to 6 times on failure. */
    private fun loadData(attempt: Int = 0) {
        val base = serverUri.trimEnd('/')
        if (attempt == 0) Log.d(TAG, "loadData start  base=$base  session=$sessionId")
        io.execute {
            val statusData = try {
                val json = httpGet("$base/session/status?workspaceId=$workspaceId")
                if (json.isNotEmpty()) {
                    val obj = JSONObject(json).optJSONObject(sessionId)
                    if (obj != null) statusFromJson(obj)
                    else { Log.w(TAG, "sessionId not in status map: $json"); StatusData.idle() }
                } else null
            } catch (e: Exception) { Log.e(TAG, "status error: $e"); null }

            val lastMsg = try {
                val json = httpGet("$base/session/$sessionId/message")
                if (json.isNotEmpty()) lastAssistantText(json, JSONArray(json)) else null
            } catch (e: Exception) { Log.e(TAG, "msg error: $e"); null }

            ui.post {
                if (statusData != null) applyStatus(statusData)
                when {
                    lastMsg != null -> setMd(messageLabel, lastMsg)
                    attempt < 6    -> ui.postDelayed({ loadData(attempt + 1) }, 1_500L)
                    else           -> if (messageLabel?.text.isNullOrEmpty())
                        messageLabel?.text = "等待消息…"
                }
            }
        }
    }

    private fun connectSse() {
        sseActive = true
        val base = serverUri.trimEnd('/')
        sseThread = Thread {
            while (sseActive) {
                var reader: BufferedReader? = null
                try {
                    // The server's SSE endpoint is /global/event.
                    // Each line is "data: {JSON}" — there are no "event:" prefix lines.
                    val conn = (URL("$base/global/event").openConnection() as HttpURLConnection).apply {
                        setRequestProperty("Accept", "text/event-stream")
                        setRequestProperty("Cache-Control", "no-cache")
                        connectTimeout = 10_000
                        readTimeout    = 0
                    }
                    sseConn = conn
                    Log.d(TAG, "SSE ok  code=${conn.responseCode}")
                    reader = BufferedReader(InputStreamReader(conn.inputStream))
                    while (sseActive) {
                        val line = reader.readLine() ?: break
                        if (line.startsWith("data: ")) {
                            handleSseData(line.removePrefix("data: "))
                        }
                    }
                    Log.d(TAG, "SSE stream ended")
                } catch (e: Exception) {
                    Log.e(TAG, "SSE error: $e  reconnecting in 3s")
                } finally {
                    runCatching { reader?.close() }
                    sseConn?.disconnect()
                    sseConn = null
                }
                if (sseActive) Thread.sleep(3_000)
            }
        }.also { it.isDaemon = true; it.start() }
    }

    /**
     * Each SSE event from the server is a single "data: {json}" line.
     * The JSON has:
     *   - "type"       : event type string  (e.g. "session.status")
     *   - "properties" : object with event-specific fields
     *       • "sessionID" identifies the relevant session
     *       • for "session.status": "status" (phase name) and optional "message"
     */
    private fun handleSseData(data: String) {
        val json  = try { JSONObject(data) } catch (_: Exception) { return }
        val type  = json.optString("type")
        val props = json.optJSONObject("properties") ?: return
        val sid   = props.optString("sessionID").takeIf { it.isNotEmpty() }
                 ?: props.optString("sessionId").takeIf { it.isNotEmpty() }  // some events use lowercase d
        val base  = serverUri.trimEnd('/')
        when (type) {
            "session.status" -> {
                if (sid == null || sid == sessionId) {
                    val s = StatusData.fromPhase(
                        props.optString("status", "idle"),
                        props.optString("message").takeIf { it.isNotEmpty() },
                    )
                    Log.d(TAG, "SSE status→${s.label}")
                    ui.post { applyStatus(s) }
                }
            }
            "message.updated", "message.part.updated", "message.part.delta",
            "session.updated" -> {
                if (sid == null || sid == sessionId) {
                    try {
                        io.execute {
                            val j = try { httpGet("$base/session/$sessionId/message") } catch (_: Exception) { "" }
                            if (j.isNotEmpty()) {
                                val text = lastAssistantText(j, JSONArray(j))
                                if (text != null) ui.post { setMd(messageLabel, text) }
                            }
                        }
                    } catch (_: Exception) { }
                }
            }
        }
    }

    // ── UI helpers ────────────────────────────────────────────────────────────

    private data class StatusData(val label: String, val dotColor: Int) {
        companion object {
            fun idle() = StatusData("完成", Color.parseColor("#30D158"))
            fun fromPhase(phase: String, msg: String?) = when (phase) {
                "busy"       -> StatusData(msg ?: "运行中…",                  Color.parseColor("#FF9F0A"))
                "retry"      -> StatusData(msg?.let { "重试 · $it" } ?: "重试中…", Color.parseColor("#FF9F0A"))
                "compacting" -> StatusData("压缩上下文…",                     Color.parseColor("#FF9F0A"))
                "error"      -> StatusData(msg ?: "出错",                    Color.parseColor("#FF453A"))
                else         -> idle()
            }
        }
    }

    private fun statusFromJson(json: JSONObject) = StatusData.fromPhase(
        json.optString("status", "idle"),
        json.optString("message").takeIf { it.isNotEmpty() },
    )

    private fun applyStatus(s: StatusData) {
        // FULL mode
        statusLabel?.text = s.label
        (dotView?.background as? GradientDrawable)?.setColor(s.dotColor)
        // MINI mode
        miniLabel?.text = s.label
        (miniDot?.background as? GradientDrawable)?.setColor(s.dotColor)
        // LINE mode
        lineStatusTv?.text = s.label
        (lineDot?.background as? GradientDrawable)?.setColor(s.dotColor)
    }

    /**
     * Build a markdown display string from the last assistant message bundle.
     * Parts are rendered in their natural chronological order so that tool
     * calls appear inline between text blocks, not all at the end.
     *
     *  reasoning → *💭 first 120 chars…*
     *  text      → main markdown content
     *  tool      → 🔧 `name` ✓/⚙/⏳/✗
     */
    private fun lastAssistantText(rawJson: String, arr: JSONArray): String? {
        for (i in arr.length() - 1 downTo 0) {
            val bundle = arr.getJSONObject(i)
            val role = bundle.optJSONObject("info")?.optString("role") ?: continue
            if (role != "assistant") continue
            val parts = bundle.optJSONArray("parts") ?: continue

            val sb = StringBuilder()

            for (j in 0 until parts.length()) {
                val part = parts.getJSONObject(j)
                val data = part.optJSONObject("data")
                when (part.optString("type")) {
                    "reasoning" -> {
                        val t = data?.optString("text")?.trim()?.takeIf { it.isNotEmpty() } ?: continue
                        val snippet = t.replace('\n', ' ').let {
                            if (it.length > 120) it.take(120) + "…" else it
                        }
                        if (sb.isNotEmpty()) sb.append("\n\n")
                        sb.append("*💭 $snippet*")
                    }
                    "text" -> {
                        val t = data?.optString("text")?.trim()?.takeIf { it.isNotEmpty() } ?: continue
                        if (sb.isNotEmpty()) sb.append("\n\n")
                        sb.append(t)
                    }
                    "tool" -> {
                        val name   = data?.optString("tool")?.takeIf { it.isNotEmpty() } ?: continue
                        val state  = data.optJSONObject("state")
                        val status = state?.optString("status") ?: "pending"
                        val icon   = when (status) {
                            "completed" -> "✓"; "error" -> "✗"; "running" -> "⚙"; else -> "⏳"
                        }
                        if (sb.isNotEmpty()) sb.append("\n")
                        sb.append("🔧 `$name` $icon")
                    }
                }
            }

            val result = sb.toString().trim()
            if (result.isNotEmpty()) {
                Log.d(TAG, "display(${result.length}): ${result.take(80)}")
                return result
            }
            val partTypes = (0 until parts.length()).map { parts.getJSONObject(it).optString("type") }
            Log.w(TAG, "no display content yet. parts=$partTypes  rawHead=${rawJson.take(200)}")
            return null
        }
        Log.w(TAG, "no assistant bundle  bundles=${arr.length()}  rawHead=${rawJson.take(200)}")
        return null
    }

    /** Render [text] as markdown in the full-mode label and update LINE/MINI labels. */
    private fun setMd(tv: TextView?, text: String) {
        tv ?: return
        lastMsgText = text
        val m = markwon
        if (m != null) m.setMarkdown(tv, text) else tv.text = text
        // Update LINE mode: show first non-blank plain text line
        val firstLine = text.lines()
            .map { it.trim().removePrefix("*").removePrefix("💭").trim() }
            .firstOrNull { it.isNotBlank() } ?: ""
        lineMsgTv?.text = firstLine
        // Auto-scroll only if the user hasn't manually scrolled away from the bottom
        if (autoScroll) {
            msgScrollView?.post { msgScrollView?.fullScroll(View.FOCUS_DOWN) }
        }
    }

    private fun httpGet(url: String): String {
        val c = URL(url).openConnection() as HttpURLConnection
        c.requestMethod  = "GET"
        c.connectTimeout = 5_000
        c.readTimeout    = 10_000
        return try {
            val code = c.responseCode
            if (code == 200) {
                c.inputStream.bufferedReader().readText()
            } else {
                Log.w(TAG, "httpGet $url → $code")
                ""
            }
        } finally {
            c.disconnect()
        }
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    private fun tearDown() {
        sseActive = false
        sseConn?.disconnect()
        sseConn = null
        sseThread?.interrupt()
        sseThread = null
        ui.removeCallbacksAndMessages(null)
        container?.let { runCatching { windowManager.removeView(it) } }
        container     = null
        wParams       = null
        miniView      = null; lineView = null; fullView = null
        miniDot       = null; miniLabel = null
        lineDot       = null; lineStatusTv = null; lineMsgTv = null
        dotView       = null; statusLabel = null
        messageLabel  = null; msgScrollView = null
        markwon       = null
        lastMsgText   = ""
    }

    private fun openMainApp() {
        // FLAG_ACTIVITY_REORDER_TO_FRONT brings the existing Activity instance to
        // the front of its task without recreating it (unlike SINGLE_TOP, which
        // creates a new instance when the activity is not already at the very top).
        startActivity(Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        })
        // Defer stopSelf() so the current touch-event chain finishes before
        // windowManager.removeView() is called inside tearDown(). Calling removeView()
        // synchronously from inside a click/touch callback can crash on some devices.
        ui.post { stopSelf() }
    }

    // ── Persistent notification ───────────────────────────────────────────────

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    NOTIF_CHANNEL_ID,
                    "Mag floating window",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        startForeground(NOTIF_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val flags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), flags)
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, NOTIF_CHANNEL_ID)
            else @Suppress("DEPRECATION") Notification.Builder(this)
        val isChinese = java.util.Locale.getDefault().language == "zh"
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(if (isChinese) "Mag 小窗运行中" else "Mag floating window active")
            .setContentText(if (isChinese) "点击返回查看会话" else "Tap to return to your session")
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    // ── Draggable container ───────────────────────────────────────────────────

    private inner class FloatingContainer : FrameLayout(this@FloatingWindowService) {

        var wm: WindowManager? = null
        var lp: WindowManager.LayoutParams? = null
        /** Views whose touches are never intercepted (buttons in the drag zone). */
        var closeBtnRef: View? = null
        private val extraNoIntercept = mutableListOf<View>()
        fun addExtraNoInterceptRef(v: View) { extraNoIntercept.add(v) }

        private val headerPx = 44f * resources.displayMetrics.density
        private var startX   = 0;  private var startY   = 0
        private var downRawX = 0f; private var downRawY = 0f
        private var dragging = false

        private fun hitsView(v: View?, rx: Float, ry: Float): Boolean {
            v ?: return false
            val loc = IntArray(2); v.getLocationOnScreen(loc)
            return rx >= loc[0] && rx <= loc[0] + v.width &&
                   ry >= loc[1] && ry <= loc[1] + v.height
        }

        override fun onInterceptTouchEvent(ev: MotionEvent) = when (ev.action) {
            MotionEvent.ACTION_DOWN -> {
                val rx = ev.rawX; val ry = ev.rawY
                // Let button touches through without intercepting
                if (hitsView(closeBtnRef, rx, ry) ||
                    extraNoIntercept.any { hitsView(it, rx, ry) }) {
                    dragging = false; false
                } else if (ev.y <= headerPx) {
                    // In MINI/LINE modes the whole bar is the "header"; allow drag everywhere
                    startX = lp?.x ?: 0; startY = lp?.y ?: 0
                    downRawX = rx; downRawY = ry
                    dragging = true; true
                } else {
                    dragging = false; false
                }
            }
            else -> dragging
        }

        override fun onTouchEvent(ev: MotionEvent): Boolean {
            val p = lp ?: return super.onTouchEvent(ev)
            if (!dragging) return super.onTouchEvent(ev)
            return when (ev.action) {
                MotionEvent.ACTION_MOVE -> {
                    val dm   = resources.displayMetrics
                    val maxX = (dm.widthPixels  - width).coerceAtLeast(0)
                    val maxY = (dm.heightPixels - height).coerceAtLeast(0)
                    // Clamp so the window never goes off-screen.
                    // Without the clamp, dragging into an edge accumulates offset that
                    // the user has to "undo" before the window moves again.
                    p.x = (startX + (ev.rawX - downRawX).roundToInt()).coerceIn(0, maxX)
                    p.y = (startY + (ev.rawY - downRawY).roundToInt()).coerceIn(0, maxY)
                    wm?.updateViewLayout(this, p)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    // Sync startX/Y to the actual clamped position so the next drag
                    // starts from where the window really is.
                    startX = p.x; startY = p.y
                    dragging = false; true
                }
                else -> true
            }
        }
    }
}
