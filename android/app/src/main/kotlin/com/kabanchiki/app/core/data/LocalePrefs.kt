package com.kabanchiki.app.core.data

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

/**
 * Per-app language via AndroidX: persisted automatically
 * (AppLocalesMetadataHolderService with autoStoreLocales=true).
 */
object LocalePrefs {

    fun current(): String {
        val locales = AppCompatDelegate.getApplicationLocales()
        return if (!locales.isEmpty && locales[0]?.language == "en") "en" else "uk"
    }

    fun apply(language: String) {
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(language))
    }
}
