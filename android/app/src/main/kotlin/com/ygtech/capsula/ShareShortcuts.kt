package com.ygtech.capsula

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build

/**
 * Publishes the "Save to Capsula" Direct Share target, which the system
 * share sheet shows in its top row, and reports its use so the sheet ranks
 * it higher over time.
 */
object ShareShortcuts {
    private const val ID = "save_to_capsula"
    private const val CATEGORY = "com.ygtech.capsula.category.SAVE_LINK"

    fun publish(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        if (manager.dynamicShortcuts.any { it.id == ID }) return

        val shortcut = ShortcutInfo.Builder(context, ID)
            .setShortLabel("Save to Capsula")
            .setLongLabel("Save to Capsula Inbox")
            .setIcon(Icon.createWithResource(context, R.mipmap.ic_launcher))
            .setCategories(setOf(CATEGORY))
            .setLongLived(true)
            // Opening the shortcut from the launcher just opens the app.
            .setIntent(
                Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN)
            )
            .build()
        try {
            manager.addDynamicShortcuts(listOf(shortcut))
        } catch (_: Exception) {
            // Rate-limited or not allowed; regular sharing still works.
        }
    }

    fun reportUsed(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        context.getSystemService(ShortcutManager::class.java)?.reportShortcutUsed(ID)
    }
}
