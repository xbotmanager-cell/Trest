package com.heydane.assistant

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings

class DeviceAutomationBridge(
    private val activity: Activity,
    private val permissionBridge: PermissionCheckBridge
) {

    fun listLaunchableApps(): List<Map<String, String>> {
        val pm = activity.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveList = pm.queryIntentActivities(mainIntent, PackageManager.MATCH_ALL)
        return resolveList
            .map { info ->
                mapOf(
                    "label" to info.loadLabel(pm).toString(),
                    "packageName" to info.activityInfo.packageName
                )
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() }
    }

    fun launchApp(packageName: String): Map<String, Any> {
        val trimmed = packageName.trim()
        if (trimmed.isEmpty()) {
            return mapOf("success" to false, "message" to "Package name must not be empty.")
        }
        val launchIntent = activity.packageManager.getLaunchIntentForPackage(trimmed)
            ?: return mapOf("success" to false, "message" to "App $trimmed is not installed or has no launcher.")
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(launchIntent)
        return mapOf("success" to true, "message" to "Launched $trimmed.")
    }

    fun openSettingPanel(panel: String): Map<String, Any> {
        val action = when (panel) {
            "wifi" -> Settings.ACTION_WIFI_SETTINGS
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
            "display" -> Settings.ACTION_DISPLAY_SETTINGS
            "sound" -> Settings.ACTION_SOUND_SETTINGS
            "accounts" -> Settings.ACTION_SYNC_SETTINGS
            "security" -> Settings.ACTION_SECURITY_SETTINGS
            else -> return mapOf("success" to false, "message" to "Unsupported settings panel: $panel")
        }
        return try {
            val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Opened $panel settings.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Unable to open $panel settings: ${e.localizedMessage}")
        }
    }

    fun performAccessibilityAction(actionName: String): Map<String, Any> {
        if (!permissionBridge.isAccessibilityEnabled()) {
            return mapOf(
                "success" to false,
                "message" to "HEY DANE Accessibility Service is disabled. Enable it in Permission Center first."
            )
        }
        val ok = DaneAccessibilityService.performSafeGlobalAction(actionName)
        return if (ok) {
            mapOf("success" to true, "message" to "Executed accessibility action: $actionName.")
        } else {
            mapOf("success" to false, "message" to "Accessibility action '$actionName' failed or is unsupported.")
        }
    }

    fun getRecentNotifications(): Map<String, Any> {
        if (!permissionBridge.isNotificationListenerEnabled()) {
            return mapOf(
                "success" to false,
                "message" to "Notification Access is not enabled.",
                "items" to emptyList<Map<String, Any>>()
            )
        }
        return mapOf(
            "success" to true,
            "message" to "Retrieved recent notifications.",
            "items" to DaneNotificationListenerService.getRecent()
        )
    }

    fun lockDeviceIfAdmin(): Map<String, Any> {
        if (!permissionBridge.isDeviceAdminEnabled()) {
            return mapOf(
                "success" to false,
                "message" to "Device Administrator is not enabled for HEY DANE."
            )
        }
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(activity, DaneDeviceAdminReceiver::class.java)
        return if (dpm.isAdminActive(admin)) {
            dpm.lockNow()
            mapOf("success" to true, "message" to "Device screen locked via DevicePolicyManager.")
        } else {
            mapOf("success" to false, "message" to "Device Admin check failed.")
        }
    }
}
