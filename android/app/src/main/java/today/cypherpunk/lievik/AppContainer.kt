package today.cypherpunk.lievik

import android.content.Context
import android.os.Build
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.data.api.ApiClient
import today.cypherpunk.lievik.data.api.ApiJson
import today.cypherpunk.lievik.data.api.LievikApi
import today.cypherpunk.lievik.data.api.MeResponse
import today.cypherpunk.lievik.data.api.Meta
import today.cypherpunk.lievik.data.api.User
import today.cypherpunk.lievik.data.api.UserUpdate
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.db.LievikDatabase
import today.cypherpunk.lievik.data.prefs.AppPrefs
import today.cypherpunk.lievik.data.prefs.SecureStore
import today.cypherpunk.lievik.data.repo.Connectivity
import today.cypherpunk.lievik.data.repo.Messages
import today.cypherpunk.lievik.data.repo.Session
import today.cypherpunk.lievik.data.repo.SyncRepository
import today.cypherpunk.lievik.util.AppLocale

/** Manual dependency injection: one of everything, created by [LievikApp]. */
class AppContainer(val context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val prefs = AppPrefs(context, scope)
    val session = Session(SecureStore(context))
    val db = LievikDatabase.create(context)
    val dao = db.dao()
    val connectivity = Connectivity(context)
    val messages = Messages()

    val client = ApiClient(
        serverUrl = { prefs.current.serverUrl },
        token = { session.token },
        language = { language() },
        userAgent = "Lievik-Android/${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}; Android ${Build.VERSION.RELEASE})",
        onUnauthorized = { scope.launch { wipeLocal(); session.signOut(forced = true) } },
    )
    val api: LievikApi get() = client.api

    val sync = SyncRepository({ api }, dao, prefs)

    private val _meta = MutableStateFlow(prefs.current.metaJson?.let { runCatching { ApiJson.decodeFromString(Meta.serializer(), it) }.getOrNull() })
    val meta: StateFlow<Meta?> = _meta

    private val _me = MutableStateFlow(prefs.current.meJson?.let { runCatching { ApiJson.decodeFromString(MeResponse.serializer(), it) }.getOrNull() })
    val me: StateFlow<MeResponse?> = _me

    val deviceName: String
        get() = listOf(Build.MANUFACTURER.replaceFirstChar { it.uppercase() }, Build.MODEL).distinct().joinToString(" ")

    fun language(): String = AppLocale.chosen() ?: prefs.current.locale ?: AppLocale.current()

    suspend fun refreshMeta(): Meta? = apiCall { api.meta() }.getOrNull()?.also { meta ->
        _meta.value = meta
        prefs.update { it.copy(metaJson = ApiJson.encodeToString(Meta.serializer(), meta)) }
    }

    suspend fun refreshMe(): MeResponse? = apiCall { api.me() }.getOrNull()?.also { setMe(it) }

    fun setMe(me: MeResponse) {
        _me.value = me
        prefs.update { it.copy(meJson = ApiJson.encodeToString(MeResponse.serializer(), me)) }
    }

    fun setUser(user: User) {
        setMe(_me.value?.copy(user = user) ?: MeResponse(user))
    }

    /** A device token arrived (any login method). */
    fun signedIn(token: String, user: User?) {
        session.signIn(token)
        user?.let { setUser(it) }
        // The app has no language of its own yet: adopt the one saved on the server.
        val saved = user?.settings?.locale
        if (AppLocale.chosen() == null && prefs.current.locale == null && saved in AppLocale.SUPPORTED) {
            prefs.update { it.copy(locale = saved) }
            AppLocale.apply(saved)
        }
        scope.launch {
            refreshMe()
            sync.sync()
        }
        SyncScheduler.schedule(context)
    }

    /** Interface language chosen in Settings: applied here and saved on the user, like the web. */
    fun changeLanguage(language: String) {
        prefs.update { it.copy(locale = language) }
        AppLocale.apply(language)
        scope.launch {
            apiCall { api.updateMe(UserUpdate(mapOf("locale" to language))) }.getOrNull()?.user?.let { setUser(it) }
        }
    }

    suspend fun signOut() {
        apiCall { api.signOut() }
        wipeLocal()
        session.signOut()
    }

    private suspend fun wipeLocal() {
        dao.clearAll()
        _me.value = null
        prefs.updateNow { it.copy(syncSince = null, syncCursor = null, lastSyncAt = 0, meJson = null) }
        SyncScheduler.cancel(context)
    }
}
