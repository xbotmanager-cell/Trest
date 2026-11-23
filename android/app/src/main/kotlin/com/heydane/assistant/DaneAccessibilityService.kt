package com.heydane.assistant

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class DaneAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile
        private var instance: DaneAccessibilityService? = null

        fun isConnected(): Boolean = instance != null

        fun performSafeGlobalAction(actionName: String): Boolean {
            val service = instance ?: return false
            val actionId = when (actionName) {
                "back" -> GLOBAL_ACTION_BACK
                "home" -> GLOBAL_ACTION_HOME
                "recents" -> GLOBAL_ACTION_RECENTS
                "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
                else -> return false
            }
            return service.performGlobalAction(actionId)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Strictly passive unless an explicit user-confirmed global action is invoked.
        // Never reads or records password fields or authentication screens.
    }

    override fun onInterrupt() {
        // No background state retained.
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }
}
