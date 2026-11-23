package com.heydane.assistant

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PLATFORM_CHANNEL = "com.heydane.assistant/platform"
        private const val PERMISSIONS_CHANNEL = "com.heydane.assistant/permissions"
        private const val AUTOMATION_CHANNEL = "com.heydane.assistant/automation"
    }

    private lateinit var permissionBridge: PermissionCheckBridge
    private lateinit var deviceAutomationBridge: DeviceAutomationBridge
    private lateinit var commsAndAlarmsBridge: CommsAndAlarmsBridge
    private lateinit var fileAutomationManager: FileAutomationManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        permissionBridge = PermissionCheckBridge(this)
        deviceAutomationBridge = DeviceAutomationBridge(this, permissionBridge)
        commsAndAlarmsBridge = CommsAndAlarmsBridge(this)
        fileAutomationManager = FileAutomationManager(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PLATFORM_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val bootPrefs = getSharedPreferences(DaneBootReceiver.PREFS_NAME, MODE_PRIVATE)
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "release" to Build.VERSION.RELEASE,
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "packageName" to applicationContext.packageName,
                            "lastBootMs" to bootPrefs.getLong(DaneBootReceiver.KEY_LAST_BOOT_MS, 0L)
                        )
                    )
                }
                "openSettings" -> {
                    val action = call.argument<String>("action")
                    if (action.isNullOrBlank()) {
                        result.error("INVALID_ACTION", "Settings action must not be blank", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(action).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", e.localizedMessage, null)
                    }
                }
                "startVoiceForegroundService" -> {
                    val micGranted = checkSelfPermission(
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!micGranted) {
                        result.error(
                            "MIC_PERMISSION_REQUIRED",
                            "RECORD_AUDIO permission must be granted before starting the microphone foreground service.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, DaneForegroundService::class.java).apply {
                        action = DaneForegroundService.ACTION_START_LISTENING
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FGS_RESTRICTED", e.localizedMessage, null)
                    }
                }
                "stopVoiceForegroundService" -> {
                    val intent = Intent(this, DaneForegroundService::class.java).apply {
                        action = DaneForegroundService.ACTION_STOP_LISTENING
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSIONS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSpecialAccessSnapshot" -> {
                    result.success(permissionBridge.getSpecialAccessSnapshot())
                }
                "openSpecialAccessSettings" -> {
                    val target = call.argument<String>("target").orEmpty()
                    result.success(permissionBridge.openSpecialAccessSettings(target))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUTOMATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "listLaunchableApps" -> result.success(deviceAutomationBridge.listLaunchableApps())
                "launchApp" -> {
                    val pkg = call.argument<String>("packageName").orEmpty()
                    result.success(deviceAutomationBridge.launchApp(pkg))
                }
                "openSettingPanel" -> {
                    val panel = call.argument<String>("panel").orEmpty()
                    result.success(deviceAutomationBridge.openSettingPanel(panel))
                }
                "performAccessibilityAction" -> {
                    val actionName = call.argument<String>("actionName").orEmpty()
                    result.success(deviceAutomationBridge.performAccessibilityAction(actionName))
                }
                "getRecentNotifications" -> result.success(deviceAutomationBridge.getRecentNotifications())
                "clearNotifications" -> {
                    DaneNotificationListenerService.clearBuffer()
                    result.success(mapOf("success" to true, "message" to "Cleared notification buffer."))
                }
                "lockDeviceAdmin" -> result.success(deviceAutomationBridge.lockDeviceIfAdmin())
                "setAlarm" -> {
                    val hour = call.argument<Int>("hour") ?: -1
                    val minute = call.argument<Int>("minute") ?: -1
                    val label = call.argument<String>("label")
                    result.success(commsAndAlarmsBridge.setAlarm(hour, minute, label))
                }
                "setTimer" -> {
                    val seconds = call.argument<Int>("seconds") ?: 0
                    val label = call.argument<String>("label")
                    result.success(commsAndAlarmsBridge.setTimer(seconds, label))
                }
                "showAlarms" -> result.success(commsAndAlarmsBridge.showAlarms())
                "openDialer" -> {
                    val phone = call.argument<String>("phoneNumber").orEmpty()
                    result.success(commsAndAlarmsBridge.openDialer(phone))
                }
                "placeCall" -> {
                    val phone = call.argument<String>("phoneNumber").orEmpty()
                    result.success(commsAndAlarmsBridge.placeDirectCall(phone))
                }
                "composeSms" -> {
                    val phone = call.argument<String>("phoneNumber").orEmpty()
                    val body = call.argument<String>("body").orEmpty()
                    result.success(commsAndAlarmsBridge.composeSms(phone, body))
                }
                "sendSms" -> {
                    val phone = call.argument<String>("phoneNumber").orEmpty()
                    val body = call.argument<String>("body").orEmpty()
                    result.success(commsAndAlarmsBridge.sendDirectSms(phone, body))
                }
                "shareText" -> {
                    val text = call.argument<String>("text").orEmpty()
                    result.success(commsAndAlarmsBridge.shareText(text))
                }
                "handoffWhatsApp" -> {
                    val phone = call.argument<String>("phoneNumber").orEmpty()
                    val text = call.argument<String>("text").orEmpty()
                    result.success(commsAndAlarmsBridge.handoffWhatsApp(phone, text))
                }
                "pickDocumentSaf" -> fileAutomationManager.pickDocumentSaf(result)
                "renameDocumentSaf" -> {
                    val uri = call.argument<String>("uri").orEmpty()
                    val newName = call.argument<String>("newName").orEmpty()
                    result.success(fileAutomationManager.renameDocumentSaf(uri, newName))
                }
                "deleteDocumentSaf" -> {
                    val uri = call.argument<String>("uri").orEmpty()
                    result.success(fileAutomationManager.deleteDocumentSaf(uri))
                }
                "queryRecentMedia" -> result.success(fileAutomationManager.queryRecentMedia())
                "enqueueDownload" -> {
                    val url = call.argument<String>("url").orEmpty()
                    val fileName = call.argument<String>("fileName").orEmpty()
                    result.success(fileAutomationManager.enqueueDownload(url, fileName))
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (fileAutomationManager.handleActivityResult(requestCode, resultCode, data)) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
