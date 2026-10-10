package today.cypherpunk.lievik.data.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import today.cypherpunk.lievik.BuildConfig

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "prefs")

/** Everything the app remembers that is not a secret, in DataStore. */
data class PrefsState(
    val serverUrl: String = BuildConfig.DEFAULT_SERVER,
    val locale: String? = null,
    val syncSince: String? = null,
    val syncCursor: String? = null,
    val lastSyncAt: Long = 0,
    val dismissedUpdate: Int = 0,
    val metaJson: String? = null,
    val meJson: String? = null,
)

/**
 * DataStore-backed prefs with an in-memory mirror, because the HTTP layer
 * needs the server URL and language synchronously on every request.
 */
class AppPrefs(context: Context, private val scope: CoroutineScope) {
    private val store = context.dataStore
    private val _state = MutableStateFlow(runBlocking { read(store.data.first()) })
    val state: StateFlow<PrefsState> = _state
    val current: PrefsState get() = _state.value

    private fun read(p: Preferences) = PrefsState(
        serverUrl = p[SERVER] ?: BuildConfig.DEFAULT_SERVER,
        locale = p[LOCALE],
        syncSince = p[SINCE],
        syncCursor = p[CURSOR],
        lastSyncAt = p[LAST_SYNC] ?: 0,
        dismissedUpdate = p[DISMISSED] ?: 0,
        metaJson = p[META],
        meJson = p[ME],
    )

    /** Applies [change] to the mirror at once and persists it in the background. */
    fun update(change: (PrefsState) -> PrefsState) {
        val next = change(_state.value)
        _state.value = next
        scope.launch { persist(next) }
    }

    /** Like [update] but waits until the change is on disk. */
    suspend fun updateNow(change: (PrefsState) -> PrefsState) {
        val next = change(_state.value)
        _state.value = next
        persist(next)
    }

    private suspend fun persist(s: PrefsState) {
        store.edit { p ->
            p[SERVER] = s.serverUrl
            p.setOrRemove(LOCALE, s.locale)
            p.setOrRemove(SINCE, s.syncSince)
            p.setOrRemove(CURSOR, s.syncCursor)
            p[LAST_SYNC] = s.lastSyncAt
            p[DISMISSED] = s.dismissedUpdate
            p.setOrRemove(META, s.metaJson)
            p.setOrRemove(ME, s.meJson)
        }
    }

    private fun <T> androidx.datastore.preferences.core.MutablePreferences.setOrRemove(key: Preferences.Key<T>, value: T?) {
        if (value == null) remove(key) else this[key] = value
    }

    private companion object {
        val SERVER = stringPreferencesKey("server_url")
        val LOCALE = stringPreferencesKey("locale")
        val SINCE = stringPreferencesKey("sync_since")
        val CURSOR = stringPreferencesKey("sync_cursor")
        val LAST_SYNC = longPreferencesKey("last_sync_at")
        val DISMISSED = intPreferencesKey("dismissed_update")
        val META = stringPreferencesKey("meta_json")
        val ME = stringPreferencesKey("me_json")
    }
}
