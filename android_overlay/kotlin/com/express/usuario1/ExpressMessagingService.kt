package com.express.usuario1

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Recibe las ofertas con la app cerrada o en segundo plano.
 *
 * El servidor manda una oferta sin aviso visible (`presentation=overlay`) solo a
 * tokens cuyo permiso de superposición estaba verificado. Aquí se pide a
 * [FloatingOfferService] que dibuje la barra. Si la ventana no se dibuja (permiso
 * retirado, Android lo rechaza, error), ese servicio muestra el aviso de respaldo.
 * Mientras la app está visible, la barra la muestra Flutter y aquí no se hace nada.
 *
 * Importante: un conductor en línea mantiene la ubicación en un servicio en primer
 * plano. Ese proceso NO está visible; por eso solo se considera visible la actividad
 * en primer plano (IMPORTANCE_FOREGROUND) o visible (IMPORTANCE_VISIBLE).
 *
 * Límites: si el proceso se detiene antes de llegar aquí, o Android retrasa el mensaje
 * (Doze, restricciones del fabricante), la oferta puede llegar tarde o no llegar.
 * Si Android tiene bloqueadas las notificaciones de Express (permiso POST_NOTIFICATIONS
 * o canal desactivado) y no hay barra, no existe ningún aviso posible: se registra en
 * logcat y no se declara respaldo garantizado.
 */
class ExpressMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        handleOffer(this, message.data)
    }

    companion object {
        private const val TAG = "ExpressOfferPush"
        private const val CHANNEL_ID = "express_urgent"
        private const val OFFER_TAG_PREFIX = "express_offer:"

        /**
         * Decide qué hacer con una oferta. Lo usa FCM y también la prueba local de QA,
         * para que ambos recorran exactamente el mismo camino.
         */
        fun handleOffer(context: Context, data: Map<String, String>) {
            val eventType = data["type"]
            // Process invalidations even if Flutter is in the foreground.
            // A late cancellation must never dismiss a newer offer.
            if (eventType == "ride_request_cancelled" ||
                eventType == "ride_cancelled" ||
                eventType == "ride_request_expired" ||
                eventType == "ride_request_assigned" ||
                eventType == "ride_assigned" ||
                eventType == "ride_request_invalidated"
            ) {
                val invalidId = data["offer_id"]?.takeIf { it.isNotBlank() }
                    ?: data["ride_request_id"]?.takeIf { it.isNotBlank() }
                    ?: return
                FloatingOfferService.hideActiveIfOfferId(invalidId)
                val manager = context.getSystemService(NotificationManager::class.java)
                manager?.cancel(OFFER_TAG_PREFIX + invalidId, 0)
                return
            }
            if (eventType != "ride_request") return
            if (isAppVisible()) return

            val offerId = data["offer_id"]?.takeIf { it.isNotBlank() }
                ?: data["ride_request_id"]?.takeIf { it.isNotBlank() }
                ?: return

            // Una oferta ya vencida no debe avisar al conductor.
            val expiresAt = data["expires_at_millis"]?.toLongOrNull() ?: 0L
            if (expiresAt > 0L && expiresAt <= System.currentTimeMillis()) {
                Log.i(TAG, "oferta vencida al llegar; no se muestra")
                return
            }

            val canDraw = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                Settings.canDrawOverlays(context)

            // Con permiso y barra pedidos, la barra manda. Si Android no la deja
            // dibujar, FloatingOfferService avisa con el respaldo.
            if (data["presentation"] == "overlay" && canDraw) {
                // Android puede rechazar el arranque desde segundo plano: en ese caso
                // también se avisa con el respaldo, para no perder la oferta.
                val started = runCatching {
                    context.startService(
                        Intent(context, FloatingOfferService::class.java)
                            .setAction(FloatingOfferService.ACTION_SHOW)
                            .putExtra(FloatingOfferService.EXTRA_OFFER_ID, offerId)
                            .putExtra(FloatingOfferService.EXTRA_SERVICE, data["service"] ?: "taxi")
                            .putExtra(FloatingOfferService.EXTRA_PRICE, data["price_label"])
                            .putExtra(FloatingOfferService.EXTRA_ROUTE, data["route_label"])
                            .putExtra(FloatingOfferService.EXTRA_EXPIRES_AT, expiresAt)
                            .putExtra(
                                FloatingOfferService.EXTRA_DISPLAY_DURATION,
                                data["display_seconds"]?.toIntOrNull() ?: 30,
                            )
                            .putExtra(FloatingOfferService.EXTRA_FALLBACK_TITLE, data["title"])
                            .putExtra(FloatingOfferService.EXTRA_FALLBACK_BODY, data["body"]),
                    )
                }.isSuccess
                if (started) return
            }

            // Sin barra (permiso o preferencia apagados, o arranque rechazado): aviso normal.
            postFallbackNotification(context, offerId, data["title"], data["body"])
        }

        // Solo la actividad visible cuenta como app abierta. Un servicio en primer plano
        // (IMPORTANCE_FOREGROUND_SERVICE) o un proceso en segundo plano no lo es.
        private fun isAppVisible(): Boolean {
            val info = ActivityManager.RunningAppProcessInfo()
            ActivityManager.getMyMemoryState(info)
            return info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
        }

        /**
         * Aviso normal de respaldo, con el mismo texto que la notificación de FCM.
         * Usa una etiqueta fija por oferta: si llega otra vez la misma oferta, reemplaza
         * el aviso en vez de duplicarlo, y no vuelve a sonar.
         * Devuelve false si Android no permite mostrar avisos de Express.
         */
        fun postFallbackNotification(
            context: Context,
            offerId: String,
            title: String?,
            body: String?,
        ): Boolean {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                Log.w(TAG, "avisos de Express desactivados: la oferta no puede mostrarse")
                return false
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = manager.getNotificationChannel(CHANNEL_ID)
                if (channel?.importance == NotificationManager.IMPORTANCE_NONE) {
                    Log.w(TAG, "canal de ofertas bloqueado por el usuario: sin aviso posible")
                    return false
                }
                if (channel == null) {
                    manager.createNotificationChannel(
                        NotificationChannel(
                            CHANNEL_ID,
                            "Viajes y ofertas Express",
                            NotificationManager.IMPORTANCE_HIGH,
                        ),
                    )
                }
            }
            // No se limpia la pila de la actividad: con singleInstance podría recrearse.
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }
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
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOnlyAlertOnce(true)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build()
            manager.notify(OFFER_TAG_PREFIX + offerId, 0, notification)
            return true
        }
    }
}
