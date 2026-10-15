package com.ygtech.capsula

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Receives links shared from other apps. Runs as a transparent window over
 * the sharing app and hands the shared text to Flutter at the `/share` route,
 * which saves it and closes this activity.
 */
class ShareActivity : FlutterActivity() {
    private var pendingShare: Map<String, String?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingShare = readShare(intent)
        super.onCreate(savedInstanceState)
        ShareShortcuts.publish(this)
        if (pendingShare != null) ShareShortcuts.reportUsed(this)
    }

    override fun getInitialRoute(): String = "/share"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShare" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readShare(intent: Intent?): Map<String, String?>? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val subject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()
        if (text.isNullOrBlank() && subject.isNullOrBlank()) return null
        return mapOf("text" to text, "subject" to subject)
    }

    private companion object {
        const val CHANNEL = "capsula/share"
    }
}
