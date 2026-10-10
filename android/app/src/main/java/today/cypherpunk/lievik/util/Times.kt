package today.cypherpunk.lievik.util

import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.ULocale
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.abs

/** ISO 8601 timestamps from the API, formatted in the app's language. */
object Times {
    fun parseMillis(iso: String?): Long? {
        if (iso.isNullOrBlank()) return null
        return runCatching { Instant.parse(iso).toEpochMilli() }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(iso).toInstant().toEpochMilli() }.getOrNull()
    }

    fun nowIso(): String = Instant.now().toString()

    fun date(iso: String?, locale: Locale = AppLocale.locale()): String {
        val millis = parseMillis(iso) ?: return ""
        return DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)
            .format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))
    }

    fun dateTime(iso: String?, locale: Locale = AppLocale.locale()): String {
        val millis = parseMillis(iso) ?: return ""
        return DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale)
            .format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))
    }

    /** "5 minutes ago", "in 2 days" — ICU, in [locale] (not the phone's language). */
    fun relative(iso: String?, now: Long = System.currentTimeMillis(), locale: Locale = AppLocale.locale()): String {
        val millis = parseMillis(iso) ?: return ""
        val diff = millis - now
        val seconds = abs(diff) / 1000
        val direction = if (diff < 0) RelativeDateTimeFormatter.Direction.LAST else RelativeDateTimeFormatter.Direction.NEXT
        val formatter = RelativeDateTimeFormatter.getInstance(ULocale.forLocale(locale))
        val (amount, unit) = when {
            seconds < 60 -> return formatter.format(RelativeDateTimeFormatter.Direction.PLAIN, RelativeDateTimeFormatter.AbsoluteUnit.NOW)
            seconds < 3600 -> seconds / 60 to RelativeDateTimeFormatter.RelativeUnit.MINUTES
            seconds < 86400 -> seconds / 3600 to RelativeDateTimeFormatter.RelativeUnit.HOURS
            seconds < 86400 * 30 -> seconds / 86400 to RelativeDateTimeFormatter.RelativeUnit.DAYS
            seconds < 86400 * 365 -> seconds / (86400 * 30) to RelativeDateTimeFormatter.RelativeUnit.MONTHS
            else -> seconds / (86400 * 365) to RelativeDateTimeFormatter.RelativeUnit.YEARS
        }
        return formatter.format(amount.toDouble(), direction, unit)
    }

    fun number(value: Number, locale: Locale = AppLocale.locale()): String =
        java.text.NumberFormat.getIntegerInstance(locale).format(value)
}
