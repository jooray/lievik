package today.cypherpunk.lievik.data.db

import androidx.room.Dao
import androidx.room.Query
import androidx.room.RawQuery
import androidx.room.Transaction
import androidx.room.Upsert
import androidx.sqlite.db.SupportSQLiteQuery
import kotlinx.coroutines.flow.Flow

@Dao
interface LievikDao {
    // ------------------------------------------------------------ sources
    @Query("SELECT * FROM sources ORDER BY distance ASC, name COLLATE NOCASE ASC")
    fun sources(): Flow<List<SourceEntity>>

    @Query("SELECT * FROM sources WHERE id = :id")
    fun source(id: Long): Flow<SourceEntity?>

    @Query("SELECT id FROM sources")
    suspend fun sourceIds(): List<Long>

    @Upsert suspend fun upsertSources(rows: List<SourceEntity>)

    @Query("DELETE FROM sources WHERE id IN (:ids)")
    suspend fun deleteSources(ids: List<Long>)

    // ------------------------------------------------------------ channels
    @Query("SELECT * FROM channels ORDER BY name COLLATE NOCASE ASC")
    fun channels(): Flow<List<ChannelEntity>>

    @Query("SELECT * FROM channels WHERE id = :id")
    fun channel(id: Long): Flow<ChannelEntity?>

    @Query("SELECT id FROM channels")
    suspend fun channelIds(): List<Long>

    @Upsert suspend fun upsertChannels(rows: List<ChannelEntity>)

    @Query("DELETE FROM channels WHERE id IN (:ids)")
    suspend fun deleteChannels(ids: List<Long>)

    // ------------------------------------------------------------ events
    @RawQuery(observedEntities = [EventEntity::class])
    fun events(query: SupportSQLiteQuery): Flow<List<EventEntity>>

    @Query("SELECT * FROM events WHERE id = :id")
    fun event(id: Long): Flow<EventEntity?>

    @Query("SELECT * FROM events ORDER BY publishedAtMillis DESC, id DESC LIMIT :limit")
    fun recentEvents(limit: Int): Flow<List<EventEntity>>

    @Query("SELECT * FROM events WHERE sourceId = :sourceId ORDER BY publishedAtMillis DESC, id DESC LIMIT :limit")
    fun sourceEvents(sourceId: Long, limit: Int): Flow<List<EventEntity>>

    @Query("SELECT * FROM events WHERE id IN (:ids)")
    suspend fun eventsByIds(ids: List<Long>): List<EventEntity>

    @Query("SELECT COUNT(*) FROM events")
    fun eventCount(): Flow<Int>

    @Upsert suspend fun upsertEvents(rows: List<EventEntity>)

    @Query("DELETE FROM events WHERE sourceId IN (:sourceIds)")
    suspend fun deleteEventsOfSources(sourceIds: List<Long>)

    // ------------------------------------------------------------ channel events
    @RawQuery(observedEntities = [ChannelEventEntity::class, EventEntity::class])
    fun curation(query: SupportSQLiteQuery): Flow<List<CurationRow>>

    @Query(
        "SELECT channel_events.*, events.* FROM channel_events JOIN events ON events.id = channel_events.ce_event_id " +
            "WHERE channel_events.ce_channel_id = :channelId AND channel_events.ce_event_id = :eventId",
    )
    fun curationRow(channelId: Long, eventId: Long): Flow<CurationRow?>

    @Query("SELECT * FROM channel_events WHERE ce_event_id = :eventId")
    fun channelEventsForEvent(eventId: Long): Flow<List<ChannelEventEntity>>

    @Query("SELECT * FROM channel_events WHERE ce_channel_id = :channelId AND ce_event_id IN (:eventIds)")
    suspend fun channelEventsFor(channelId: Long, eventIds: List<Long>): List<ChannelEventEntity>

    @Query(
        "SELECT SUM(CASE WHEN ce_used = 0 THEN 1 ELSE 0 END) AS unused, SUM(CASE WHEN ce_used = 1 THEN 1 ELSE 0 END) AS used " +
            "FROM channel_events WHERE ce_channel_id = :channelId AND ce_score >= :threshold",
    )
    fun usageCounts(channelId: Long, threshold: Int): Flow<UsageCounts>

    @Upsert suspend fun upsertChannelEvents(rows: List<ChannelEventEntity>)

    @Query("UPDATE channel_events SET ce_used = :used, ce_used_at = :usedAt WHERE ce_channel_id = :channelId AND ce_event_id IN (:eventIds)")
    suspend fun setUsed(channelId: Long, eventIds: List<Long>, used: Boolean, usedAt: String?)

    @Query("DELETE FROM channel_events WHERE ce_channel_id IN (:channelIds)")
    suspend fun deleteChannelEventsOfChannels(channelIds: List<Long>)

    @Query("DELETE FROM channel_events WHERE ce_event_id IN (SELECT id FROM events WHERE sourceId IN (:sourceIds))")
    suspend fun deleteChannelEventsOfSources(sourceIds: List<Long>)

    // ------------------------------------------------------------ contents
    @Query("SELECT * FROM contents WHERE channelId = :channelId ORDER BY updatedAt DESC")
    fun contents(channelId: Long): Flow<List<ContentEntity>>

    @Query("SELECT * FROM contents WHERE channelId = :channelId")
    suspend fun contentsOnce(channelId: Long): List<ContentEntity>

    @Query("DELETE FROM contents WHERE channelId = :channelId")
    suspend fun clearContents(channelId: Long)

    @Upsert suspend fun upsertContents(rows: List<ContentEntity>)

    @Query("DELETE FROM contents WHERE channelId IN (:channelIds)")
    suspend fun deleteContentsOfChannels(channelIds: List<Long>)

    @Transaction
    suspend fun replaceContents(channelId: Long, rows: List<ContentEntity>) {
        clearContents(channelId)
        upsertContents(rows)
    }

    // ------------------------------------------------------------ wipe
    @Query("DELETE FROM sources") suspend fun clearSources()
    @Query("DELETE FROM channels") suspend fun clearChannels()
    @Query("DELETE FROM events") suspend fun clearEvents()
    @Query("DELETE FROM channel_events") suspend fun clearChannelEvents()
    @Query("DELETE FROM contents") suspend fun clearAllContents()

    @Transaction
    suspend fun clearAll() {
        clearChannelEvents(); clearEvents(); clearAllContents(); clearChannels(); clearSources()
    }

    /**
     * One /sync page, applied atomically (docs/API_V1.md "Sync"): the source
     * and channel tables become the returned lists; events of sources that
     * disappeared and ratings of channels that disappeared are deleted; the
     * rest is upserted. See [SyncMerge] for which ids count as removed.
     */
    @Transaction
    suspend fun applySyncPage(
        sources: List<SourceEntity>,
        channels: List<ChannelEntity>,
        events: List<EventEntity>,
        channelEvents: List<ChannelEventEntity>,
    ) {
        val removedSources = SyncMerge.removed(sourceIds(), sources.map { it.id })
        val removedChannels = SyncMerge.removed(channelIds(), channels.map { it.id })
        if (removedSources.isNotEmpty()) {
            deleteChannelEventsOfSources(removedSources)
            deleteEventsOfSources(removedSources)
            deleteSources(removedSources)
        }
        if (removedChannels.isNotEmpty()) {
            deleteChannelEventsOfChannels(removedChannels)
            deleteContentsOfChannels(removedChannels)
            deleteChannels(removedChannels)
        }
        upsertSources(sources)
        upsertChannels(channels)
        // Never resurrect events of a source removed in this same page.
        upsertEvents(SyncMerge.keepEvents(events, removedSources))
        upsertChannelEvents(SyncMerge.keepChannelEvents(channelEvents, removedChannels))
    }
}

data class UsageCounts(val unused: Int?, val used: Int?)
