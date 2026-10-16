package com.express.usuario1

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

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
                if ((Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !Settings.canDrawOverlays(ctx)) ||
                    expiresAt <= System.currentTimeMillis()) {
                    result.success(false)
                    return
                }
                try {
                    // Android may forbid background service starts. In that
                    // case the existing push notification remains the fallback.
                    result.success(ctx.startService(intent) != null)
                } catch (error: RuntimeException) {
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

        @Volatile
        private var active: FloatingOfferPlugin? = null

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
