package com.express.usuario1

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * Tarjeta flotante de una oferta de Taxi o Envíos. Solo se muestra cuando la
 * app Flutter lo pide (política en Dart) y se cierra al expirar, al actuar o
 * cuando la app vuelve al primer plano. No concede permisos.
 */
class FloatingOfferService : Service() {
    private var windowManager: WindowManager? = null
    private var card: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var expiry: Runnable? = null
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

    private fun show(intent: Intent) {
        // Quita solo la tarjeta anterior: el servicio sigue vivo para la nueva.
        removeCard()
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        val id = intent.getStringExtra(EXTRA_OFFER_ID) ?: run { stopSelf(); return }
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(this).inflate(R.layout.express_floating_offer, null)
        view.findViewById<TextView>(R.id.offer_title).text =
            intent.getStringExtra(EXTRA_SERVICE) ?: "Oferta Express"
        view.findViewById<TextView>(R.id.offer_price).text =
            intent.getStringExtra(EXTRA_PRICE) ?: ""
        view.findViewById<TextView>(R.id.offer_route).text =
            intent.getStringExtra(EXTRA_ROUTE) ?: ""
        view.findViewById<Button>(R.id.offer_accept).setOnClickListener {
            FloatingOfferPlugin.emitAction(id, "accept")
            openApp()
            hide()
        }
        view.findViewById<Button>(R.id.offer_reject).setOnClickListener {
            FloatingOfferPlugin.emitAction(id, "reject")
            hide()
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP
        try {
            wm.addView(view, params)
        } catch (e: RuntimeException) {
            // Permiso revocado o restricción del sistema: sin tarjeta, sin overlays huérfanos.
            stopSelf()
            return
        }
        windowManager = wm
        card = view
        offerId = id

        // Expiración real: la tarjeta desaparece cuando vence la oferta.
        val expiresAt = intent.getLongExtra(EXTRA_EXPIRES_AT, 0L)
        val delay = expiresAt - System.currentTimeMillis()
        if (delay <= 0L) {
            hide()
        } else {
            expiry = Runnable { hide() }
            handler.postDelayed(expiry!!, delay)
        }
    }

    private fun openApp() {
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            startActivity(it)
        }
    }

    /** Quita la tarjeta y cancela su expiración, sin detener el servicio. */
    private fun removeCard() {
        expiry?.let { handler.removeCallbacks(it) }
        expiry = null
        card?.let { runCatching { windowManager?.removeView(it) } }
        card = null
        offerId = null
    }

    /** Oculta la tarjeta y detiene el servicio. */
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
