package com.example.mdscr

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class ConnectionKeepAliveService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val stopService = Runnable { stopSelf() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == stopAction) {
            stopSelf()
            return START_NOT_STICKY
        }
        val graceSeconds = intent?.getIntExtra(graceSecondsExtra, 120) ?: 120
        createNotificationChannel()
        val stopIntent = PendingIntent.getService(
            this,
            stopPendingIntentRequestCode,
            Intent(this, ConnectionKeepAliveService::class.java).setAction(stopAction),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        startForeground(notificationId, NotificationCompat.Builder(this, notificationChannelId)
            .setContentTitle("MDSCR active in background")
            .setContentText("Keeping the signal connection active")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "STOP BACKGROUND CONNECTION",
                stopIntent,
            )
            .build())
        handler.removeCallbacks(stopService)
        if (graceSeconds != permanentGraceSeconds) {
            handler.postDelayed(stopService, graceSeconds.coerceAtLeast(0) * 1000L)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopService)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            notificationChannelId,
            "Background connection",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val graceSecondsExtra = "graceSeconds"
        private const val permanentGraceSeconds = -1
        private const val stopAction = "com.example.mdscr.STOP_BACKGROUND_CONNECTION"
        private const val notificationChannelId = "background_connection"
        private const val notificationId = 1001
        private const val stopPendingIntentRequestCode = 1001
    }
}
