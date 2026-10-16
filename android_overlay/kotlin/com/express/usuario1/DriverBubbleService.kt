package com.express.usuario1

import android.app.ActivityManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import kotlin.math.abs

/**
 * Burbuja circular de acceso directo a Express. Es independiente de la tarjeta de
 * ofertas: no muestra datos de viaje ni acepta nada. La controla Dart; solo existe
 * mientras Express está en segundo plano y el conductor está disponible.
 *
 * Gestos: arrastrar libremente, soltar en un borde (se ajusta al borde más cercano),
 * tocar para abrir Express, arrastrar hasta el destino inferior «✕» para descartarla.
 * Descartar no desconecta al conductor: Dart recuerda la decisión.
 */
class DriverBubbleService : Service() {
    private var windowManager: WindowManager? = null
    private var bubble: View? = null
    private var dismissTarget: View? = null
    private var dismissTargetParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> show()
            ACTION_HIDE -> hide()
        }
        return START_NOT_STICKY
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun show() {
        if (bubble != null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm
        val size = dp(56)
        val metrics = resources.displayMetrics

        val icon = ImageView(this).apply {
            setImageResource(R.drawable.ic_express_notification_large)
            scaleType = ImageView.ScaleType.CENTER_CROP
            setPadding(dp(4), dp(4), dp(4), dp(4))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke(dp(2), Color.rgb(11, 87, 208))
            }
            outlineProvider = ViewOutlineProvider.BACKGROUND
            clipToOutline = true
            elevation = dp(6).toFloat()
            contentDescription = "Abrir Express"
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS

        val params = WindowManager.LayoutParams(size, size, type, flags, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            x = metrics.widthPixels - size - dp(8)
            y = (metrics.heightPixels * 0.45f).toInt()
        }

        val slop = ViewConfiguration.get(this).scaledTouchSlop
        var downRawX = 0f
        var downRawY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        icon.setOnTouchListener { view, event ->
            val lp = view.layoutParams as WindowManager.LayoutParams
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = lp.x
                    startY = lp.y
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!dragging && (abs(dx) > slop || abs(dy) > slop)) {
                        dragging = true
                        showDismissTarget()
                    }
                    if (dragging) {
                        lp.x = startX + dx.toInt()
                        lp.y = startY + dy.toInt()
                        wm.updateViewLayout(view, lp)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!dragging) {
                        // Tap: open Express. Dart hides the bubble once Express is visible.
                        removeDismissTarget()
                        FloatingOfferPlugin.emitBubble("open_app")
                        openApp()
                        hide()
                    } else if (isOverDismissTarget(lp, size, metrics.heightPixels)) {
                        removeDismissTarget()
                        FloatingOfferPlugin.emitBubble("dismissed")
                        hide()
                    } else {
                        removeDismissTarget()
                        snapToEdge(view, lp, size, metrics.widthPixels, metrics.heightPixels)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    removeDismissTarget()
                    true
                }
                else -> false
            }
        }

        try {
            wm.addView(icon, params)
        } catch (_: RuntimeException) {
            // Android can deny the window even with permission; nothing to clean up.
            stopSelf()
            return
        }
        bubble = icon
        active = true
    }

    private fun showDismissTarget() {
        if (dismissTarget != null) return
        val wm = windowManager ?: return
        val size = dp(64)
        val target = TextView(this).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.rgb(180, 35, 24))
            }
            contentDescription = "Descartar burbuja"
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(
            size,
            size,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.START
            x = (resources.displayMetrics.widthPixels - size) / 2
            y = dp(72)
        }
        try {
            wm.addView(target, params)
            dismissTarget = target
            dismissTargetParams = params
        } catch (_: RuntimeException) {
            // Without the target the user can still drop the bubble at an edge.
        }
    }

    private fun removeDismissTarget() {
        dismissTarget?.let { runCatching { windowManager?.removeView(it) } }
        dismissTarget = null
        dismissTargetParams = null
    }

    private fun isOverDismissTarget(lp: WindowManager.LayoutParams, size: Int, screenHeight: Int): Boolean {
        val target = dismissTargetParams ?: return false
        val bubbleCenterX = lp.x + size / 2
        val bubbleCenterY = lp.y + size / 2
        val targetCenterX = target.x + target.width / 2
        val targetCenterY = screenHeight - target.y - target.height / 2
        val dx = bubbleCenterX - targetCenterX
        val dy = bubbleCenterY - targetCenterY
        return dx * dx + dy * dy < dp(56) * dp(56)
    }

    private fun snapToEdge(
        view: View,
        lp: WindowManager.LayoutParams,
        size: Int,
        screenWidth: Int,
        screenHeight: Int,
    ) {
        val margin = dp(8)
        val centerX = lp.x + size / 2
        lp.x = if (centerX < screenWidth / 2) margin else screenWidth - size - margin
        lp.y = lp.y.coerceIn(dp(24), screenHeight - size - dp(24))
        windowManager?.updateViewLayout(view, lp)
    }

    private fun openApp() {
        // Mismo criterio que la tarjeta: traer la tarea propia al frente en lugar
        // de crear una segunda Activity singleInstance.
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val restored = runCatching {
            val ownTask = activityManager.appTasks.firstOrNull { task ->
                val base = task.taskInfo.baseIntent
                base?.component?.packageName == packageName || base?.getPackage() == packageName
            }
            if (ownTask != null) {
                ownTask.moveToFront()
                true
            } else {
                false
            }
        }.getOrDefault(false)
        if (restored) return
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        runCatching { startActivity(launch) }
    }

    private fun hide() {
        removeDismissTarget()
        bubble?.let { runCatching { windowManager?.removeView(it) } }
        bubble = null
        active = false
        stopSelf()
    }

    override fun onDestroy() {
        removeDismissTarget()
        bubble?.let { runCatching { windowManager?.removeView(it) } }
        bubble = null
        active = false
        super.onDestroy()
    }

    companion object {
        const val ACTION_SHOW = "com.express.usuario1.driver_bubble.SHOW"
        const val ACTION_HIDE = "com.express.usuario1.driver_bubble.HIDE"

        @Volatile
        var active = false
            private set
    }
}
