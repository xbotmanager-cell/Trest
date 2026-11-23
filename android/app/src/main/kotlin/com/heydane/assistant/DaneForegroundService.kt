package com.heydane.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class DaneForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "hey_dane_voice_channel"
        const val NOTIFICATION_ID = 4101
        const val ACTION_START_LISTENING = "com.heydane.assistant.action.START_LISTENING"
        const val ACTION_STOP_LISTENING = "com.heydane.assistant.action.STOP_LISTENING"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_LISTENING) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        ensureNotificationChannel()
        val notification = buildActiveNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        isRunning = true
        return START_NOT_STICKY
    }

    private fun buildActiveNotification(): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val openPending = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, DaneForegroundService::class.java).apply {
            action = ACTION_STOP_LISTENING
        }
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("HEY DANE Voice Active")
            .setContentText("Microphone monitoring is visible and active. Tap Stop to end.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "Stop Listening",
                    stopPending
                ).build()
            )
            .build()
    }

    private fun ensureNotificationChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "HEY DANE Active Voice",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Displays when HEY DANE microphone session is active."
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun stopForegroundCompat() {
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }
}
