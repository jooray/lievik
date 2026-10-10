package today.cypherpunk.lievik.util

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import java.util.Locale

/**
 * The interface language: en, sk, cs or es, like the web. Stored as the
 * per-app locale (AppCompat keeps it on Android < 13, the system on 13+).
 */
object AppLocale {
    val SUPPORTED = listOf("en", "sk", "cs", "es")

    /** The app's explicit choice, or null when it follows the phone. */
    fun chosen(): String? {
        val list = AppCompatDelegate.getApplicationLocales()
        if (list.isEmpty) return null
        return list[0]?.language?.takeIf { it in SUPPORTED }
    }

    /** The language in effect: the app's choice, else the phone's if supported, else English. */
    fun current(): String {
        chosen()?.let { return it }
        val system = LocaleListCompat.getAdjustedDefault()
        for (i in 0 until system.size()) {
            val language = system[i]?.language
            if (language in SUPPORTED) return language!!
        }
        return "en"
    }

    fun locale(): Locale = Locale.forLanguageTag(current())

    fun apply(language: String?) {
        AppCompatDelegate.setApplicationLocales(
            if (language == null) LocaleListCompat.getEmptyLocaleList() else LocaleListCompat.forLanguageTags(language),
        )
    }

    /** Native name of each language, as the web's switcher shows it. */
    fun displayName(code: String) = when (code) {
        "en" -> "English"
        "sk" -> "Slovenčina"
        "cs" -> "Čeština"
        "es" -> "Español"
        else -> code
    }
}
