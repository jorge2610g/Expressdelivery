package com.express.usuario1

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Canal «express/floating_offers». Expone el permiso oficial de superposición
 * y arranca/detiene la tarjeta. Las acciones del conductor vuelven a Dart.
 */
class FloatingOfferPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        active = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        if (active === this) active = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.success(false)
        when (call.method) {
            "hasPermission" -> result.success(
                Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)
            )
            "openPermissionSettings" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + ctx.packageName)
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    ctx.startActivity(intent)
                    result.success(null)
                } catch (error: RuntimeException) {
                    result.success(false)
                }
            }
            "show" -> {
                val args = call.arguments as? Map<*, *> ?: return result.success(false)
                val intent = Intent(ctx, FloatingOfferService::class.java)
                    .setAction(FloatingOfferService.ACTION_SHOW)
                    .putExtra(FloatingOfferService.EXTRA_OFFER_ID, args["offerId"] as? String)
                    .putExtra(FloatingOfferService.EXTRA_SERVICE, args["service"] as? String)
                    .putExtra(FloatingOfferService.EXTRA_PRICE, args["priceLabel"] as? String)
                    .putExtra(FloatingOfferService.EXTRA_ROUTE, args["routeLabel"] as? String)
                    .putExtra(
                        FloatingOfferService.EXTRA_DISPLAY_DURATION,
                        (args["displayDurationSeconds"] as? Number)?.toInt() ?: 15
                    )
                    .putExtra(
                        FloatingOfferService.EXTRA_EXPIRES_AT,
                        (args["expiresAtMillis"] as? Number)?.toLong() ?: 0L
                    )
                val expiresAt = (args["expiresAtMillis"] as? Number)?.toLong() ?: 0L
                val offerId = args["offerId"] as? String
                if (offerId.isNullOrBlank() ||
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !Settings.canDrawOverlays(ctx)) ||
                    expiresAt <= System.currentTimeMillis()) {
                    result.success(false)
                    return
                }
                // startService solo significa que el servicio arrancó. La barra
                // cuenta como mostrada únicamente cuando el servicio confirma que
                // la ventana quedó adherida (completeShow). Si no llega a tiempo,
                // se responde false y la notificación de respaldo se conserva.
                val previous = pendingShows.put(offerId, result)
                previous?.success(false)
                val timeout = Runnable {
                    if (pendingShows.remove(offerId, result)) result.success(false)
                }
                mainHandler.postDelayed(timeout, SHOW_CONFIRM_TIMEOUT_MS)
                try {
                    // Android may forbid background service starts. In that
                    // case the existing push notification remains the fallback.
                    if (ctx.startService(intent) == null) {
                        pendingShows.remove(offerId, result)
                        result.success(false)
                    }
                } catch (error: RuntimeException) {
                    pendingShows.remove(offerId, result)
                    result.success(false)
                }
            }
            "consumePendingOpen" -> {
                // A Flutter engine can be destroyed while Express is behind
                // another app. Return the user's last tap once when the new
                // authenticated driver screen is ready. The app MUST recheck
                // account/channel/offer expiry against the server.
                val prefs = ctx.getSharedPreferences(PENDING_OPEN_PREFS, Context.MODE_PRIVATE)
                val id = prefs.getString("offerId", null)
                val clickedAt = prefs.getLong("clickedAtMillis", 0L)
                prefs.edit().remove("offerId").remove("clickedAtMillis").apply()
                val age = System.currentTimeMillis() - clickedAt
                result.success(if (!id.isNullOrBlank() && age in 0L..120000L) id else null)
            }
            "bubbleShow" -> {
                // La burbuja es un acceso directo permanente en segundo plano, separado
                // de la tarjeta de ofertas. Sin permiso de superposición no se muestra.
                val canDraw = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                    Settings.canDrawOverlays(ctx)
                if (!canDraw) {
                    result.success(false)
                    return
                }
                try {
                    ctx.startService(
                        Intent(ctx, DriverBubbleService::class.java)
                            .setAction(DriverBubbleService.ACTION_SHOW)
                    )
                    result.success(true)
                } catch (error: RuntimeException) {
                    result.success(false)
                }
            }
            "bubbleHide" -> {
                if (DriverBubbleService.active) {
                    try {
                        ctx.startService(
                            Intent(ctx, DriverBubbleService::class.java)
                                .setAction(DriverBubbleService.ACTION_HIDE)
                        )
                    } catch (error: RuntimeException) {
                        // Service already stopping; the bubble is gone either way.
                    }
                }
                result.success(null)
            }
            "hide" -> {
                if (!FloatingOfferService.hideActive()) {
                    try {
                        ctx.startService(
                            Intent(ctx, FloatingOfferService::class.java)
                                .setAction(FloatingOfferService.ACTION_HIDE)
                        )
                    } catch (error: RuntimeException) {
                        // A stopped service has no visible card to remove.
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "express/floating_offers"
        private const val PENDING_OPEN_PREFS = "express_floating_offer_open_v1"
        private const val SHOW_CONFIRM_TIMEOUT_MS = 3000L

        @Volatile
        private var active: FloatingOfferPlugin? = null

        // Respuestas de "show" esperando que el servicio confirme la ventana.
        private val pendingShows = ConcurrentHashMap<String, MethodChannel.Result>()
        private val mainHandler = Handler(Looper.getMainLooper())

        /** Llamado por FloatingOfferService tras addView (true) o cualquier rechazo (false). */
        fun completeShow(offerId: String, shown: Boolean) {
            val result = pendingShows.remove(offerId) ?: return
            mainHandler.post { result.success(shown) }
        }

        /** Eventos de la burbuja hacia Dart: "open_app" o "dismissed". */
        fun emitBubble(action: String) {
            active?.channel?.invokeMethod("bubbleEvent", mapOf("action" to action))
        }

        fun emitAction(context: Context, offerId: String, action: String) {
            if (action == "open") {
                // Save the user's explicit tap before launching the Activity;
                // MethodChannel delivery alone is lost after a cold start.
                context.getSharedPreferences(PENDING_OPEN_PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString("offerId", offerId)
                    .putLong("clickedAtMillis", System.currentTimeMillis())
                    .apply()
                // The main Activity reads this once after its Flutter driver
                // screen is ready. Avoid racing an in-memory callback against
                // Activity startup or opening the same offer twice.
                return
            }
            active?.channel?.invokeMethod(
                "action",
                mapOf("offerId" to offerId, "action" to action)
            )
        }
    }
}
