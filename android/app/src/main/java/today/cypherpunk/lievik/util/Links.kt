package today.cypherpunk.lievik.util

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent

object Links {
    /** A web page in a Custom Tab, falling back to any browser. */
    fun openUrl(context: Context, url: String) {
        val uri = Uri.parse(url)
        try {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, uri)
        } catch (e: ActivityNotFoundException) {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    /** Any URI (nostr:, nostrconnect:, https:) handed to whatever app handles it. */
    fun openExternal(context: Context, uri: String): Boolean = try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    data class App(val packageName: String, val label: String)

    /** Installed apps that open a NIP-21 `nostr:` link (Amethyst, Primal, Yakihonne…), by name. */
    fun nostrApps(context: Context, nostrUri: String): List<App> {
        val pm = context.packageManager
        return pm.queryIntentActivities(Intent(Intent.ACTION_VIEW, Uri.parse(nostrUri)), PackageManager.MATCH_DEFAULT_ONLY)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { (pkg, _) -> pkg != context.packageName }
            .distinctBy { it.first }
            .map { (pkg, label) -> App(pkg, label) }
            .sortedBy { it.label.lowercase() }
    }

    fun openInApp(context: Context, uri: String, packageName: String): Boolean = try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setPackage(packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    fun canOpen(context: Context, uri: String): Boolean =
        Intent(Intent.ACTION_VIEW, Uri.parse(uri)).resolveActivity(context.packageManager) != null

    fun copy(context: Context, label: String, text: String) {
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(label, text))
    }

    fun share(context: Context, text: String, subject: String? = null) {
        val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        if (!subject.isNullOrBlank()) intent.putExtra(Intent.EXTRA_SUBJECT, subject)
        context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
