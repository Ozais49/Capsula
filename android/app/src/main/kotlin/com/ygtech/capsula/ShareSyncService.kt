package com.ygtech.capsula

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Keeps the app running while a shared link is finished in the background
 * (its title fetched, the bookmark synced) after the share window has hidden.
 *
 * Without it, Android treats an app with no visible window as idle and may
 * freeze or stop it within seconds, so the title would never arrive. A
 * foreground service is the supported way to finish short work after the
 * user has left; it shows a quiet notification while it runs.
 *
 * Runs at most [MAX_RUN_MS]; Flutter stops it sooner when the work is done.
 */
class ShareSyncService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val stopper = Runnable { stopSelf() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        handler.removeCallbacks(stopper)
        handler.postDelayed(stopper, MAX_RUN_MS)
        return START_NOT_STICKY
    }

    /** Short services must stop when told they've run too long. */
    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopper)
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Saving shared links",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown briefly while a shared link's title is fetched"
                    setShowBadge(false)
                }
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Saving to Capsula…")
            .setContentText("Getting the title")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "share_sync"
        private const val NOTIFICATION_ID = 41
        private const val MAX_RUN_MS = 45_000L

        fun start(context: Context) {
            val intent = Intent(context, ShareSyncService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ShareSyncService::class.java))
        }
    }
}
