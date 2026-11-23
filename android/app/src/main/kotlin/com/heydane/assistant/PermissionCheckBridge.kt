package com.heydane.assistant

import android.app.Activity
import android.app.AlarmManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils

class PermissionCheckBridge(private val activity: Activity) {

    fun getSpecialAccessSnapshot(): Map<String, Any> {
        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "accessibilityEnabled" to isAccessibilityEnabled(),
            "notificationAccessEnabled" to isNotificationListenerEnabled(),
            "deviceAdminEnabled" to isDeviceAdminEnabled(),
            "overlayEnabled" to Settings.canDrawOverlays(activity),
            "exactAlarmEnabled" to isExactAlarmAllowed(),
            "batteryOptimizationIgnored" to isIgnoringBatteryOptimizations(),
            "foregroundServiceRunning" to DaneForegroundService.isRunning
        )
    }

    fun isAccessibilityEnabled(): Boolean {
        if (DaneAccessibilityService.isConnected()) return true
        val expectedComponent = ComponentName(activity, DaneAccessibilityService::class.java)
            .flattenToString()
        val enabledServices = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabledServices)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expectedComponent, ignoreCase = true)) {
                return true
            }
        }
        return false
    }

    fun isNotificationListenerEnabled(): Boolean {
        if (DaneNotificationListenerService.isConnected()) return true
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val expected = ComponentName(activity, DaneNotificationListenerService::class.java)
            .flattenToString()
        return flat.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    fun isDeviceAdminEnabled(): Boolean {
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(activity, DaneDeviceAdminReceiver::class.java)
        return dpm.isAdminActive(adminComponent)
    }

    fun isExactAlarmAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = activity.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(activity.packageName)
    }

    fun openSpecialAccessSettings(target: String): Boolean {
        return try {
            val intent = when (target) {
                "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                "notifications" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                "overlay" -> Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activity.packageName}")
                )
                "exactAlarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:${activity.packageName}")
                    )
                } else {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
                }
                "battery" -> Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${activity.packageName}")
                )
                "deviceAdmin" -> {
                    val adminComponent = ComponentName(activity, DaneDeviceAdminReceiver::class.java)
                    Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                        putExtra(
                            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                            activity.getString(R.string.device_admin_description)
                        )
                    }
                }
                else -> Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${activity.packageName}")
                )
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
