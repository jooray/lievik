package today.cypherpunk.lievik.data.repo

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import today.cypherpunk.lievik.data.prefs.SecureStore

/**
 * The signed-in state: just whether this device holds an API token. The token
 * itself stays in [SecureStore] and is only read by the HTTP layer.
 */
class Session(private val secure: SecureStore) {
    @Volatile private var cached: String? = secure.get(KEY)
    private val _signedIn = MutableStateFlow(cached != null)
    val signedIn: StateFlow<Boolean> = _signedIn

    /** True when the last sign-out was forced by the server (token revoked/expired). */
    val expired = MutableStateFlow(false)

    val token: String? get() = cached

    fun signIn(token: String) {
        secure.put(KEY, token)
        cached = token
        expired.value = false
        _signedIn.value = true
    }

    fun signOut(forced: Boolean = false) {
        secure.put(KEY, null)
        cached = null
        expired.value = forced
        _signedIn.value = false
    }

    private companion object {
        const val KEY = "api_token"
    }
}
