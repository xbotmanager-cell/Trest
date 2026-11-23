package com.heydane.assistant

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.CopyOnWriteArrayList

data class CapturedNotification(
    val packageName: String,
    val title: String,
    val text: String,
    val postTime: Long
)

class DaneNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val MAX_BUFFER = 25
        private val recentNotifications = CopyOnWriteArrayList<CapturedNotification>()

        @Volatile
        private var connected: Boolean = false

        fun isConnected(): Boolean = connected

        fun getRecent(): List<Map<String, Any>> {
            return recentNotifications.map {
                mapOf(
                    "packageName" to it.packageName,
                    "title" to it.title,
                    "text" to it.text,
                    "postTime" to it.postTime
                )
            }
        }

        fun clearBuffer() {
            recentNotifications.clear()
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        connected = true
    }

    override fun onListenerDisconnected() {
        connected = false
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return
        if (sbn.packageName == applicationContext.packageName) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return

        recentNotifications.add(
            0,
            CapturedNotification(
                packageName = sbn.packageName,
                title = title,
                text = text,
                postTime = sbn.postTime
            )
        )
        while (recentNotifications.size > MAX_BUFFER) {
            recentNotifications.removeAt(recentNotifications.lastIndex)
        }
    }
}
