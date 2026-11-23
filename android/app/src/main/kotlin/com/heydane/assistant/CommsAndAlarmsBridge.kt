package com.heydane.assistant

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.telephony.SmsManager

class CommsAndAlarmsBridge(private val activity: Activity) {

    fun setAlarm(hour: Int, minute: Int, message: String?): Map<String, Any> {
        if (hour !in 0..23 || minute !in 0..59) {
            return mapOf("success" to false, "message" to "Invalid alarm time $hour:$minute.")
        }
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour)
            putExtra(AlarmClock.EXTRA_MINUTES, minute)
            if (!message.isNullOrBlank()) {
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
            }
            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Opened Clock to set alarm for %02d:%02d.".format(hour, minute))
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Unable to invoke Clock app: ${e.localizedMessage}")
        }
    }

    fun setTimer(seconds: Int, message: String?): Map<String, Any> {
        if (seconds <= 0) {
            return mapOf("success" to false, "message" to "Timer duration must be greater than 0 seconds.")
        }
        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
            putExtra(AlarmClock.EXTRA_LENGTH, seconds)
            if (!message.isNullOrBlank()) {
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
            }
            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Opened Clock to start a ${seconds}s timer.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Unable to set timer: ${e.localizedMessage}")
        }
    }

    fun showAlarms(): Map<String, Any> {
        return try {
            val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Opened Clock alarms list to review or cancel alarms.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Unable to open Clock alarms: ${e.localizedMessage}")
        }
    }

    fun openDialer(phoneNumber: String): Map<String, Any> {
        val sanitized = phoneNumber.trim()
        if (sanitized.isEmpty()) {
            return mapOf("success" to false, "message" to "Phone number is required.")
        }
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${Uri.encode(sanitized)}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Opened phone dialer for $sanitized.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Unable to open dialer: ${e.localizedMessage}")
        }
    }

    fun placeDirectCall(phoneNumber: String): Map<String, Any> {
        val sanitized = phoneNumber.trim()
        if (sanitized.isEmpty()) {
            return mapOf("success" to false, "message" to "Phone number is required.")
        }
        val granted = activity.checkSelfPermission(
            Manifest.permission.CALL_PHONE
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            return mapOf(
                "success" to false,
                "message" to "CALL_PHONE permission is not granted. Opening dialer instead is safer."
            )
        }
        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:${Uri.encode(sanitized)}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Initiated call to $sanitized.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Failed to place call: ${e.localizedMessage}")
        }
    }

    fun composeSms(phoneNumber: String, body: String): Map<String, Any> {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:${Uri.encode(phoneNumber.trim())}")).apply {
            putExtra("sms_body", body)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Opened SMS composer for $phoneNumber.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Unable to open SMS app: ${e.localizedMessage}")
        }
    }

    fun sendDirectSms(phoneNumber: String, body: String): Map<String, Any> {
        val target = phoneNumber.trim()
        val message = body.trim()
        if (target.isEmpty() || message.isEmpty()) {
            return mapOf("success" to false, "message" to "Recipient number and message body are required.")
        }
        val granted = activity.checkSelfPermission(
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            return mapOf(
                "success" to false,
                "message" to "SEND_SMS permission is not granted. Use Compose SMS or Sharesheet instead."
            )
        }
        return try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                activity.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            smsManager.sendTextMessage(target, null, message, null, null)
            mapOf("success" to true, "message" to "Dispatched SMS to $target via Android SmsManager.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "SMS dispatch failed: ${e.localizedMessage}")
        }
    }

    fun shareText(text: String): Map<String, Any> {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        val chooser = Intent.createChooser(intent, "Share via HEY DANE").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            activity.startActivity(chooser)
            mapOf("success" to true, "message" to "Opened Android Sharesheet.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Sharesheet failed: ${e.localizedMessage}")
        }
    }

    fun handoffWhatsApp(phoneNumber: String, text: String): Map<String, Any> {
        val digits = phoneNumber.replace(Regex("[^0-9]"), "")
        val url = if (digits.isNotEmpty()) {
            "https://wa.me/$digits?text=${Uri.encode(text)}"
        } else {
            "https://wa.me/?text=${Uri.encode(text)}"
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            activity.startActivity(intent)
            mapOf("success" to true, "message" to "Handed off message draft to WhatsApp. Confirm sending inside WhatsApp.")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "WhatsApp is unavailable: ${e.localizedMessage}")
        }
    }
}
