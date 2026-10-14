package com.ygtech.capsula

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity : FlutterActivity() {
    /** Bytes waiting for the user to pick where to save them. */
    private var pendingSave: Pair<ByteArray, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingSave != null) {
                    result.error("busy", "A save is already in progress", null)
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name") ?: "capsula-export"
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                pendingSave = bytes to result
                // System "Save as" dialog; no storage permission needed.
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(mimeType)
                    .putExtra(Intent.EXTRA_TITLE, name)
                startActivityForResult(intent, SAVE_REQUEST)
            }
    }

    @Deprecated("Needed for startActivityForResult in FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val (bytes, result) = pendingSave ?: return
        pendingSave = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        try {
            val stream = contentResolver.openOutputStream(uri)
                ?: throw IOException("Could not open the chosen file")
            stream.use { it.write(bytes) }
            result.success(true)
        } catch (e: Exception) {
            result.error("write_failed", e.message, null)
        }
    }

    private companion object {
        const val FILES_CHANNEL = "capsula/files"
        const val SAVE_REQUEST = 4201
    }
}
