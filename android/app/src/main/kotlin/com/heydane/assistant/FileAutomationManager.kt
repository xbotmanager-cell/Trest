package com.heydane.assistant

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel

class FileAutomationManager(private val activity: Activity) {
    companion object {
        const val REQUEST_OPEN_DOCUMENT = 5101
    }

    private var pendingPickerResult: MethodChannel.Result? = null

    fun pickDocumentSaf(result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("PICKER_BUSY", "File picker is already active.", null)
            return
        }
        pendingPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_OPEN_DOCUMENT)
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_OPEN_DOCUMENT) return false
        val callback = pendingPickerResult ?: return true
        pendingPickerResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(mapOf("success" to false, "message" to "File selection cancelled."))
            return true
        }

        val uri = data.data!!
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) {}

        val displayName = queryDisplayName(uri)
        callback.success(
            mapOf(
                "success" to true,
                "uri" to uri.toString(),
                "name" to displayName,
                "message" to "Selected $displayName via Storage Access Framework."
            )
        )
        return true
    }

    fun renameDocumentSaf(uriString: String, newName: String): Map<String, Any> {
        val cleanName = newName.trim()
        if (cleanName.isEmpty() || cleanName.contains('/') || cleanName.contains("..")) {
            return mapOf("success" to false, "message" to "Invalid target filename.")
        }
        return try {
            val uri = Uri.parse(uriString)
            val renamedUri = DocumentsContract.renameDocument(activity.contentResolver, uri, cleanName)
            if (renamedUri != null) {
                mapOf(
                    "success" to true,
                    "uri" to renamedUri.toString(),
                    "message" to "Renamed document to $cleanName."
                )
            } else {
                mapOf("success" to false, "message" to "Document provider declined rename.")
            }
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Rename failed: ${e.localizedMessage}")
        }
    }

    fun deleteDocumentSaf(uriString: String): Map<String, Any> {
        return try {
            val uri = Uri.parse(uriString)
            val deleted = DocumentsContract.deleteDocument(activity.contentResolver, uri)
            if (deleted) {
                mapOf("success" to true, "message" to "Deleted selected document.")
            } else {
                mapOf("success" to false, "message" to "Document provider declined deletion.")
            }
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Delete failed: ${e.localizedMessage}")
        }
    }

    fun queryRecentMedia(limit: Int = 20): Map<String, Any> {
        val items = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.SIZE
        )
        val sortOrder = "${MediaStore.Files.FileColumns.DATE_ADDED} DESC"
        return try {
            activity.contentResolver.query(
                MediaStore.Files.getContentUri("external"),
                projection,
                null,
                null,
                sortOrder
            )?.use { cursor ->
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                while (cursor.moveToNext() && items.size < limit) {
                    items.add(
                        mapOf(
                            "name" to (cursor.getString(nameCol) ?: "Unknown"),
                            "mimeType" to (cursor.getString(mimeCol) ?: "application/octet-stream"),
                            "sizeBytes" to cursor.getLong(sizeCol)
                        )
                    )
                }
            }
            mapOf("success" to true, "items" to items, "message" to "Loaded ${items.size} MediaStore entries.")
        } catch (e: Exception) {
            mapOf("success" to false, "items" to items, "message" to "MediaStore query failed: ${e.localizedMessage}")
        }
    }

    fun enqueueDownload(url: String, fileName: String): Map<String, Any> {
        val trimmedUrl = url.trim()
        if (!trimmedUrl.startsWith("https://")) {
            return mapOf("success" to false, "message" to "Only HTTPS download URLs are permitted.")
        }
        val safeName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        return try {
            val request = DownloadManager.Request(Uri.parse(trimmedUrl)).apply {
                setTitle(safeName)
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeName)
            }
            val dm = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val downloadId = dm.enqueue(request)
            mapOf("success" to true, "downloadId" to downloadId, "message" to "Enqueued download #$downloadId ($safeName).")
        } catch (e: Exception) {
            mapOf("success" to false, "message" to "Download failed: ${e.localizedMessage}")
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    return cursor.getString(0) ?: "Selected File"
                }
            }
        return uri.lastPathSegment ?: "Selected File"
    }
}
