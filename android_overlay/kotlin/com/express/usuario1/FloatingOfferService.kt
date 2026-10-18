package com.express.usuario1

import android.app.ActivityManager
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ProgressBar
import android.widget.TextView
import kotlin.math.abs

/**
 * Preview-only of a currently authorized Taxi/Envíos offer. This component
 * never submits bids, accepts or rejects rides. Tap opens the original offer
 * popup in Flutter, which rechecks account, channel and expiry on the server.
 * Permission is always user-controlled; no bypass of Android restricted settings.
 */
class FloatingOfferService : Service() {
    private var windowManager: WindowManager? = null
    private var card: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var ticker: Runnable? = null
    private var offerId: String? = null
    private var serverExpiresAtMillis: Long = 0L
    // Alerta sonora: una reproducción por oferta; se detiene al cerrar la tarjeta.
    private var alertPlayer: MediaPlayer? = null
    private var alertOfferId: String? = null
    private val alertStopper = Runnable { stopAlert() }

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
        val incoming = intent.getStringExtra(EXTRA_OFFER_ID)?.takeIf { it.isNotBlank() }
        // Misma oferta ya dibujada (reintento de FCM): la ventana actual sigue sin cambios.
        if (incoming != null && card != null && drawnOfferId == incoming) return
        removeCard()
        val id = incoming ?: run { stopSelf(); return }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)) {
            fallbackOrRefuse(intent, id)
            return
        }

        val expiresAt = intent.getLongExtra(EXTRA_EXPIRES_AT, 0L)
        val initialRemaining = expiresAt - System.currentTimeMillis()
        if (initialRemaining <= 0L || wasDismissed(id)) {
            refuse(id)
            return
        }
        val seconds = intent.getIntExtra(EXTRA_DISPLAY_DURATION, DEFAULT_BANNER_SECONDS)
            .coerceIn(10, 30)
        val visualExpiresAt = getVisualDeadline(id, expiresAt, seconds)
        if (visualExpiresAt <= System.currentTimeMillis()) {
            refuse(id)
            return
        }

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(this).inflate(R.layout.express_floating_offer, null)
        val header = view.findViewById<View>(R.id.offer_card_root)
        header.background = GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(Color.rgb(23, 43, 67), Color.rgb(11, 24, 42))
        ).apply {
            cornerRadius = dp(16).toFloat()
            setStroke(dp(1), Color.rgb(56, 103, 140))
        }
        view.findViewById<TextView>(R.id.offer_title).text =
            when (intent.getStringExtra(EXTRA_SERVICE)) {
                "taxi" -> "EXPRESS · NUEVO VIAJE"
                "delivery" -> "EXPRESS · NUEVO ENVÍO"
                else -> "EXPRESS · NUEVA SOLICITUD"
            }
        view.findViewById<TextView>(R.id.offer_price).text =
            intent.getStringExtra(EXTRA_PRICE) ?: "Precio no disponible"
        view.findViewById<TextView>(R.id.offer_route).text =
            intent.getStringExtra(EXTRA_ROUTE) ?: "Toca para ver los detalles"
        // Logo oficial de Express para Taxi y Envíos: el servicio se distingue en el título.
        view.findViewById<android.widget.ImageView>(R.id.offer_service_icon)
            .setImageResource(R.drawable.ic_express_notification_large)

        // The overlay only opens the original in-app offer. It never accepts.
        val openOffer = View.OnClickListener {
            FloatingOfferPlugin.emitAction(this, id, "open")
            // The native overlay must disappear as soon as Express opens.
            dismiss()
            openApp()
        }
        header.setOnClickListener(openOffer)
        view.findViewById<View>(R.id.offer_close).setOnClickListener { dismiss() }

        // Left, right or upward swipe dismisses the WHOLE overlay. Short taps
        // open the native Express task and its existing offer popup.
        var downX = 0f
        var downY = 0f
        var dragging = false
        header.setOnTouchListener { touched, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && (abs(dx) > dp(8) || abs(dy) > dp(8))) dragging = true
                    // Sigue el dedo en horizontal o hacia arriba, con desvanecimiento.
                    if (dragging && abs(dx) >= abs(dy)) {
                        view.translationX = dx
                        view.alpha = (1f - abs(dx) / (view.width * 1.2f)).coerceIn(0.4f, 1f)
                    } else if (dragging && dy < 0f) {
                        view.translationY = dy
                        view.alpha = (1f + dy / dp(220).toFloat()).coerceIn(0.4f, 1f)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    val sideways = abs(dx) > dp(40) && abs(dx) > abs(dy) * 0.7f
                    val upwards = dy < -dp(40) && abs(dy) > abs(dx) * 0.7f
                    when {
                        sideways -> flingOut(
                            view,
                            if (dx > 0f) view.width.toFloat() else -view.width.toFloat(),
                            0f,
                        )
                        upwards -> flingOut(view, 0f, -dp(260).toFloat())
                        else -> {
                            settleBack(view)
                            if (!dragging) touched.performClick()
                        }
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    settleBack(view)
                    true
                }
                else -> true
            }
        }

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
            fallbackOrRefuse(intent, id)
            return
        }
        windowManager = wm
        card = view
        offerId = id
        // Confirmación real: la ventana quedó añadida, no solo el servicio arrancado.
        drawnOfferId = id
        startAlert(id, seconds)
        // Solo aquí la barra existe de verdad: recién entonces Dart retira el
        // aviso local de respaldo. Antes de este punto la notificación sigue viva.
        FloatingOfferPlugin.completeShow(id, true)

        // Hasta 30 s visibles, pero nunca más allá de la vigencia real.
        // La cancelación/adjudicación requiere invalidación activa desde backend.
        serverExpiresAtMillis = expiresAt
        val remainingText = view.findViewById<TextView>(R.id.offer_remaining)
        remainingText.background = GradientDrawable().apply {
            setColor(Color.rgb(21, 64, 60))
            cornerRadius = dp(8).toFloat()
        }
        view.findViewById<TextView>(R.id.offer_close).background =
            GradientDrawable().apply {
                setColor(Color.rgb(44, 63, 84))
                cornerRadius = dp(8).toFloat()
            }
        val progress = view.findViewById<ProgressBar>(R.id.offer_progress)
        val life = (visualExpiresAt - System.currentTimeMillis()).coerceAtLeast(1L)
        val update = object : Runnable {
            override fun run() {
                if (offerId != id) return
                val left = (visualExpiresAt - System.currentTimeMillis()).coerceAtLeast(0L)
                if (left <= 0L) {
                    dismiss()
                    return
                }
                val seconds = (left + 999L) / 1000L
                remainingText.text = "${seconds}s"
                progress.progress = (1000L * left / life).coerceIn(0L, 1000L).toInt()
                handler.postDelayed(this, 250L)
            }
        }
        ticker = update
        handler.post(update)
    }

    private fun openApp(): Boolean {
        // ZEGO requires singleInstance for full-screen incoming voice calls.
        // Do not start a second Flutter Activity/task from a Service while
        // the original map is already alive: that can leave a black Surface.
        // Move our own existing task to the foreground first.
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val restored = runCatching {
            val ownTask = activityManager.appTasks.firstOrNull { task ->
                val base = task.taskInfo.baseIntent
                base?.component?.packageName == packageName ||
                    base?.getPackage() == packageName
            }
            if (ownTask != null) {
                ownTask.moveToFront()
                true
            } else {
                false
            }
        }.getOrDefault(false)
        if (restored) return true

        // Cold start: the OS has no existing task to recover. Do not combine
        // NEW_TASK with REORDER_TO_FRONT / CLEAR_TOP against singleInstance.
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: return false
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return runCatching {
            startActivity(launch)
            true
        }.getOrDefault(false)
    }

    // Remember dismissals until the REAL offer expiry so the same offer
    // cannot reappear after a swipe, timeout, or return to Android Home.
    private fun wasDismissed(id: String): Boolean {
        val prefs = getSharedPreferences(DISMISSED_PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val until = prefs.getLong(id, 0L)
        if (until > now) return true
        // If a former service was killed, keep the original visual deadline.
        val visualDeadline = prefs.getLong("shown:$id", 0L)
        if (visualDeadline != 0L && visualDeadline <= now) return true
        if (until != 0L) prefs.edit().remove(id).apply()
        return false
    }

    private fun getVisualDeadline(id: String, serverExpiresAt: Long, seconds: Int): Long {
        val prefs = getSharedPreferences(DISMISSED_PREFS, Context.MODE_PRIVATE)
        val key = "shown:$id"
        val recorded = prefs.getLong(key, 0L)
        // Do not extend a 30-second banner because another realtime update
        // changed the price or a new Android service instance was created.
        val deadline = if (recorded != 0L) recorded else {
            minOf(serverExpiresAt, System.currentTimeMillis() + seconds * 1000L)
                .also { prefs.edit().putLong(key, it).apply() }
        }
        return minOf(serverExpiresAt, deadline)
    }

    private fun rememberDismissal() {
        val id = offerId ?: return
        val now = System.currentTimeMillis()
        val prefs = getSharedPreferences(DISMISSED_PREFS, Context.MODE_PRIVATE)
        val edit = prefs.edit()
        // Purge expired IDs; keep local preferences bounded across many offers.
        for ((key, value) in prefs.all) {
            if (value is Long && value <= now) edit.remove(key)
        }
        if (serverExpiresAtMillis > now) edit.putLong(id, serverExpiresAtMillis)
        edit.apply()
    }

    private fun dismiss() {
        stopAlert()
        rememberDismissal()
        hide()
    }

    // Una sola alerta por oferta. No suena en silencio/vibración ni con
    // "No molestar"; se corta a los 30 s o al cerrar la tarjeta.
    private fun startAlert(id: String, seconds: Int) {
        if (alertOfferId == id) return
        stopAlert()
        val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audio == null || audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val notifications = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (notifications != null &&
            notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
        ) return
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return
        alertOfferId = id
        alertPlayer = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@FloatingOfferService, uri)
                isLooping = true
                prepare()
                start()
            }
        }.getOrNull()
        handler.postDelayed(alertStopper, minOf(seconds, 30) * 1000L)
    }

    private fun stopAlert() {
        handler.removeCallbacks(alertStopper)
        alertPlayer?.let { runCatching { it.stop() }; runCatching { it.release() } }
        alertPlayer = null
        alertOfferId = null
    }

    // El gesto sigue al dedo; al soltar, sale de pantalla o vuelve a su sitio.
    private fun flingOut(target: View, toX: Float, toY: Float) {
        stopAlert()
        target.animate().translationX(toX).translationY(toY).alpha(0f)
            .setDuration(160)
            .withEndAction { dismiss() }
            .start()
    }

    private fun settleBack(target: View) {
        target.animate().translationX(0f).translationY(0f).alpha(1f)
            .setDuration(150)
            .start()
    }

    private fun removeCard() {
        stopAlert()
        ticker?.let { handler.removeCallbacks(it) }
        ticker = null
        card?.let { runCatching { windowManager?.removeView(it) } }
        card = null
        offerId = null
        drawnOfferId = null
        serverExpiresAtMillis = 0L
    }

    // Sin ventana dibujada, la oferta pasa al aviso de respaldo si el emisor lo pidió.
    private fun fallbackOrRefuse(intent: Intent, id: String) {
        val title = intent.getStringExtra(EXTRA_FALLBACK_TITLE)
        val body = intent.getStringExtra(EXTRA_FALLBACK_BODY)
        if (title != null || body != null) {
            ExpressMessagingService.postFallbackNotification(this, id, title, body)
        }
        refuse(id)
    }

    private fun hide() {
        rememberDismissal()
        removeCard()
        stopSelf()
    }

    // The window was never shown: report it so Dart keeps the push notification
    // as the fallback. Not a user dismissal, so the offer is not remembered.
    private fun refuse(id: String) {
        FloatingOfferPlugin.completeShow(id, false)
        stopSelf()
    }

    override fun onDestroy() {
        stopAlert()
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

        /**
         * Realtime/consulta autorizada confirmó que ESTA solicitud ya no está
         * disponible. Nunca cerrar la barra de una solicitud distinta que haya
         * llegado mientras la comprobación anterior estaba en curso.
         */
        fun hideActiveIfOfferId(offerId: String): Boolean {
            val active = activeInstance ?: return false
            if (drawnOfferId != offerId) return false
            active.handler.post {
                if (active.offerId == offerId) active.hide()
            }
            return true
        }

        private const val DEFAULT_BANNER_SECONDS = 30
        private const val DISMISSED_PREFS = "express_floating_offer_dismissed_v1"
        const val ACTION_SHOW = "com.express.usuario1.floating_offer.SHOW"
        const val ACTION_HIDE = "com.express.usuario1.floating_offer.HIDE"
        const val EXTRA_FALLBACK_TITLE = "fallbackTitle"
        const val EXTRA_FALLBACK_BODY = "fallbackBody"

        /** Oferta cuya ventana está dibujada ahora mismo; null si no hay ventana. */
        @Volatile
        var drawnOfferId: String? = null

        const val EXTRA_OFFER_ID = "offerId"
        const val EXTRA_SERVICE = "service"
        const val EXTRA_PRICE = "priceLabel"
        const val EXTRA_ROUTE = "routeLabel"
        const val EXTRA_EXPIRES_AT = "expiresAtMillis"
        const val EXTRA_DISPLAY_DURATION = "displayDurationSeconds"
    }
}
