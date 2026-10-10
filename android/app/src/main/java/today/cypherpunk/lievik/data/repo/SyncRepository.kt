package today.cypherpunk.lievik.data.repo

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.LievikApi
import today.cypherpunk.lievik.data.api.SyncResponse
import today.cypherpunk.lievik.data.db.ChannelEntity
import today.cypherpunk.lievik.data.db.ChannelEventEntity
import today.cypherpunk.lievik.data.db.EventEntity
import today.cypherpunk.lievik.data.db.LievikDao
import today.cypherpunk.lievik.data.db.SourceEntity
import today.cypherpunk.lievik.data.prefs.AppPrefs

data class SyncState(val running: Boolean = false, val lastError: ApiError? = null)

/**
 * Keeps the local database in step with the server through GET /sync
 * (docs/API_V1.md "Sync"). The first run pages through `cursor`; later runs
 * ask only for what changed since the stored `server_time`. A cursor is kept
 * between pages, so an interrupted initial sync resumes where it stopped.
 */
class SyncRepository(
    private val api: () -> LievikApi,
    private val dao: LievikDao,
    private val prefs: AppPrefs,
) {
    private val mutex = Mutex()
    private val _state = MutableStateFlow(SyncState())
    val state: StateFlow<SyncState> = _state

    /** Runs a sync unless one is already running. Returns false on failure. */
    suspend fun sync(): Boolean {
        if (mutex.isLocked) return true
        return mutex.withLock {
            _state.value = SyncState(running = true)
            val result = runCatching { pull() }
            val error = result.exceptionOrNull()?.let { if (it is kotlinx.coroutines.CancellationException) throw it else ApiError.from(it) }
            _state.value = SyncState(running = false, lastError = error)
            error == null
        }
    }

    private suspend fun pull() {
        try {
            pullPages()
        } catch (e: Exception) {
            // A cursor or since the server no longer accepts (422 invalid): start the window over.
            val error = ApiError.from(e)
            if (error !is ApiError.Validation) throw e
            prefs.updateNow { it.copy(syncSince = null, syncCursor = null) }
            pullPages()
        }
    }

    private suspend fun pullPages() {
        var cursor = prefs.current.syncCursor
        do {
            // Later pages send only the cursor: it carries `since` (docs/API_V1.md "Sync").
            val since = if (cursor == null) prefs.current.syncSince?.takeIf { it.isNotBlank() } else null
            val page: SyncResponse = api().sync(since, cursor)
            apply(page)
            cursor = page.nextCursor
            if (cursor == null) {
                prefs.updateNow { it.copy(syncSince = page.serverTime, syncCursor = null, lastSyncAt = System.currentTimeMillis()) }
            } else {
                prefs.updateNow { it.copy(syncCursor = cursor) }
            }
        } while (cursor != null)
    }

    suspend fun apply(page: SyncResponse) {
        dao.applySyncPage(
            sources = page.sources.map(SourceEntity::from),
            channels = page.channels.map(ChannelEntity::from),
            events = page.events.map(EventEntity::from),
            channelEvents = page.channelEvents.map(ChannelEventEntity::from),
        )
    }

    /** Forgets the sync position and downloads everything again. */
    suspend fun fullResync(): Boolean {
        mutex.withLock {
            prefs.updateNow { it.copy(syncSince = null, syncCursor = null) }
            dao.clearAll()
        }
        return sync()
    }
}
