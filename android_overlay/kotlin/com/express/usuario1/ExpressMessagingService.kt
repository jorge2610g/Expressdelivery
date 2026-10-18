package com.express.usuario1

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
 * conductores con la sobreposición activa. Aquí se muestra la barra de oferta.
 * Si la barra no puede mostrarse (permiso retirado o fallo), se muestra un aviso
 * normal de respaldo con el mismo texto. Mientras la app está abierta, la barra la
 * muestra Flutter, así que aquí no se hace nada.
 */
class ExpressMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data["type"] != "ride_request") return
        if (isAppInForeground()) return

        val offerId = data["offer_id"]?.takeIf { it.isNotBlank() }
            ?: data["ride_request_id"]?.takeIf { it.isNotBlank() }
            ?: return

        val overlayRequested = data["presentation"] == "overlay"
        val canDraw = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(this)

        if (overlayRequested && canDraw) {
            // Android puede rechazar el arranque desde segundo plano: en ese caso se
            // cae al aviso de respaldo en lugar de perder la oferta.
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
                        ),
                )
            }.isSuccess
            if (started) return
        }

        // Respaldo: sin barra posible, se avisa con una notificación normal.
        if (overlayRequested) showFallbackNotification(data, offerId)
    }

    private fun isAppInForeground(): Boolean {
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        return info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
    }

    private fun showFallbackNotification(data: Map<String, String>, offerId: String) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Viajes y ofertas Express",
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
        val pending = PendingIntent.getActivity(
            this,
            offerId.hashCode(),
            launch ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_express)
            .setContentTitle(data["title"] ?: "Express")
            .setContentText(data["body"] ?: "Tienes una nueva solicitud cercana.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify(offerId.hashCode(), notification)
    }

    companion object {
        private const val CHANNEL_ID = "express_urgent"
    }
}
