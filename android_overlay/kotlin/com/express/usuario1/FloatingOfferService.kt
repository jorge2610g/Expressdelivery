package com.express.usuario1

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView

/**
 * Preview-only of a currently authorized Taxi/Envíos offer. This component
 * never submits bids, accepts or rejects rides. Tap opens the original offer
 * popup in Flutter, which rechecks account, channel and expiry on the server.
 * Permission is always user-controlled; no bypass of Android restricted settings.
 */
class FloatingOfferService : Service() {
    private var windowManager: WindowManager? = null
    private var card: View? = null
    private var bubble: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var ticker: Runnable? = null
    private var offerId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> show(intent)
            ACTION_HIDE -> hide()
        }
        return START_NOT_STICKY
    }

    private fun dp(value: Int): Int =
        (resources.displayMetrics.density * value + 0.5f).toInt()

    private fun show(intent: Intent) {
        removeCard()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }

        val id = intent.getStringExtra(EXTRA_OFFER_ID)?.takeIf { it.isNotBlank() }
            ?: run { stopSelf(); return }
        val expiresAt = intent.getLongExtra(EXTRA_EXPIRES_AT, 0L)
        val initialRemaining = expiresAt - System.currentTimeMillis()
        if (initialRemaining <= 0L) {
            stopSelf()
            return
        }

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(this).inflate(R.layout.express_floating_offer, null)
        val header = view.findViewById<View>(R.id.offer_card_root)
        header.background = GradientDrawable().apply {
            setColor(Color.rgb(48, 55, 70))
            cornerRadius = dp(16).toFloat()
        }
        view.findViewById<TextView>(R.id.offer_title).text =
            when (intent.getStringExtra(EXTRA_SERVICE)) {
                "taxi" -> "Express · Nuevo viaje"
                "delivery" -> "Express · Nuevo envío"
                else -> "Express · Nueva solicitud"
            }
        view.findViewById<TextView>(R.id.offer_price).text =
            intent.getStringExtra(EXTRA_PRICE) ?: "Precio no disponible"
        view.findViewById<TextView>(R.id.offer_route).text =
            intent.getStringExtra(EXTRA_ROUTE) ?: "Toca para ver los detalles"

        // The overlay is just a safe entrance to the offer detail, not a bid.
        val openOffer = View.OnClickListener {
            FloatingOfferPlugin.emitAction(this, id, "open")
            openApp()
            hide()
        }
        header.setOnClickListener(openOffer)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val flagsOverlay = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        val width = resources.displayMetrics.widthPixels - dp(24)
        val params = WindowManager.LayoutParams(
            width.coerceAtLeast(dp(260)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            flagsOverlay,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(8)
        }

        try {
            wm.addView(view, params)
        } catch (_: RuntimeException) {
            // Android may deny a window even when permission was granted.
            stopSelf()
            return
        }
        windowManager = wm
        card = view
        offerId = id

        // Separate small Express shortcut like the reference recording.
        // Its failure must never remove or duplicate the notification fallback.
        try {
            val shortcut = ImageView(this).apply {
                setImageResource(R.mipmap.ic_launcher)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                setPadding(dp(3), dp(3), dp(3), dp(3))
                background = GradientDrawable().apply {
                    setColor(Color.rgb(48, 55, 70))
                    cornerRadius = dp(13).toFloat()
                }
                contentDescription = "Abrir nueva solicitud Express"
                setOnClickListener(openOffer)
            }
            val shortcutParams = WindowManager.LayoutParams(
                dp(50), dp(50), type, flagsOverlay, PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = dp(8)
                y = dp(214)
            }
            wm.addView(shortcut, shortcutParams)
            bubble = shortcut
        } catch (_: RuntimeException) {
            bubble = null
        }

        // Real server expiry: a monotonic-looking progress bar (derived from
        // wall clock against the authoritative expiry), updated 4x per second.
        val remainingText = view.findViewById<TextView>(R.id.offer_remaining)
        val progress = view.findViewById<ProgressBar>(R.id.offer_progress)
        val life = initialRemaining.coerceAtLeast(1L)
        val update = object : Runnable {
            override fun run() {
                if (offerId != id) return
                val left = (expiresAt - System.currentTimeMillis()).coerceAtLeast(0L)
                if (left <= 0L) {
                    hide()
                    return
                }
                val seconds = (left + 999L) / 1000L
                remainingText.text = "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"
                progress.progress = (1000L * left / life).coerceIn(0L, 1000L).toInt()
                handler.postDelayed(this, 250L)
            }
        }
        ticker = update
        handler.post(update)
    }

    private fun openApp() {
        // OPEN is not ACCEPT: Flutter must check this offer is still authorized.
        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            launch.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            runCatching { startActivity(launch) }
        }
    }

    private fun removeCard() {
        ticker?.let { handler.removeCallbacks(it) }
        ticker = null
        card?.let { runCatching { windowManager?.removeView(it) } }
        bubble?.let { runCatching { windowManager?.removeView(it) } }
        card = null
        bubble = null
        offerId = null
    }

    private fun hide() {
        removeCard()
        stopSelf()
    }

    override fun onDestroy() {
        if (activeInstance === this) activeInstance = null
        removeCard()
        super.onDestroy()
    }

    companion object {
        @Volatile
        private var activeInstance: FloatingOfferService? = null

        fun hideActive(): Boolean {
            val active = activeInstance ?: return false
            active.handler.post { active.hide() }
            return true
        }

        const val ACTION_SHOW = "com.express.usuario1.floating_offer.SHOW"
        const val ACTION_HIDE = "com.express.usuario1.floating_offer.HIDE"
        const val EXTRA_OFFER_ID = "offerId"
        const val EXTRA_SERVICE = "service"
        const val EXTRA_PRICE = "priceLabel"
        const val EXTRA_ROUTE = "routeLabel"
        const val EXTRA_EXPIRES_AT = "expiresAtMillis"
    }
}
