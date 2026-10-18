package com.express.usuario1

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Recibe las ofertas con la app cerrada o en segundo plano.
 *
 * El servidor manda una oferta sin aviso visible (`presentation=overlay`) solo a
 * tokens cuyo permiso de superposición estaba verificado. Aquí se pide a
 * [FloatingOfferService] que dibuje la barra. Si la ventana no se dibuja (permiso
 * retirado, Android lo rechaza, error), ese servicio muestra el aviso de respaldo.
 * Mientras la app está en primer plano, la barra la muestra Flutter y aquí no se hace nada.
 *
 * Límites: si el proceso se detiene antes de llegar aquí, o Android retrasa el mensaje
 * (Doze, restricciones del fabricante), la oferta puede llegar tarde o no llegar.
 */
class ExpressMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data["type"] != "ride_request") return
        if (isAppInForeground()) return

        val offerId = data["offer_id"]?.takeIf { it.isNotBlank() }
            ?: data["ride_request_id"]?.takeIf { it.isNotBlank() }
            ?: return

        // Misma oferta dos veces seguidas (reintento de FCM): no se muestra de nuevo.
        if (lastReceivedOfferId == offerId) return
        lastReceivedOfferId = offerId

        val overlayRequested = data["presentation"] == "overlay"
        val canDraw = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(this)

        if (!overlayRequested) return // Notificación normal: la muestra Android.

        if (!canDraw) {
            postFallbackNotification(this, offerId, data["title"], data["body"])
            return
        }

        // Android puede rechazar el arranque desde segundo plano: en ese caso también
        // se avisa con el respaldo, para no perder la oferta.
        val started = runCatching {
            startService(
                Intent(this, FloatingOfferService::class.java)
                    .setAction(FloatingOfferService.ACTION_SHOW)
                    .putExtra(FloatingOfferService.EXTRA_OFFER_ID, offerId)
                    .putExtra(FloatingOfferService.EXTRA_SERVICE, data["service"] ?: "taxi")
                    .putExtra(FloatingOfferService.EXTRA_PRICE, data["price_label"])
                    .putExtra(FloatingOfferService.EXTRA_ROUTE, data["route_label"])
                    .putExtra(
                        FloatingOfferService.EXTRA_EXPIRES_AT,
                        data["expires_at_millis"]?.toLongOrNull() ?: 0L,
                    )
                    .putExtra(
                        FloatingOfferService.EXTRA_DISPLAY_DURATION,
                        data["display_seconds"]?.toIntOrNull() ?: 30,
                    )
                    .putExtra(FloatingOfferService.EXTRA_FALLBACK_TITLE, data["title"])
                    .putExtra(FloatingOfferService.EXTRA_FALLBACK_BODY, data["body"]),
            )
        }.isSuccess
        if (!started) postFallbackNotification(this, offerId, data["title"], data["body"])
    }

    private fun isAppInForeground(): Boolean {
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        return info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
    }

    companion object {
        private const val CHANNEL_ID = "express_urgent"

        @Volatile
        private var lastReceivedOfferId: String? = null

        /** Aviso normal de respaldo, con el mismo texto que la notificación de FCM. */
        fun postFallbackNotification(
            context: Context,
            offerId: String,
            title: String?,
            body: String?,
        ) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Viajes y ofertas Express",
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                )
            }
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
            val pending = PendingIntent.getActivity(
                context,
                offerId.hashCode(),
                launch ?: Intent(),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_express)
                .setContentTitle(title ?: "Express")
                .setContentText(body ?: "Tienes una nueva solicitud cercana.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build()
            manager.notify(offerId.hashCode(), notification)
        }
    }
}
