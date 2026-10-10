package today.cypherpunk.lievik.data.db

import androidx.sqlite.db.SimpleSQLiteQuery

enum class CurationSort(val wire: String) {
    Relevance("relevance"), Newest("newest"), Oldest("oldest");

    companion object {
        fun fromWire(value: String?) = entries.firstOrNull { it.wire == value } ?: Relevance
    }
}

/**
 * The channel curation queue, run locally with the web's semantics
 * (ChannelsController#show):
 *
 * - only ratings at or above the channel's threshold (unrated rows never match);
 * - unused only, unless [showUsed] — then used ones are pinned to the bottom
 *   whatever the sort;
 * - [search] is a plain substring of the content (LIKE with escaped
 *   metacharacters, so a "%" does not match everything);
 * - relevance = score desc; newest/oldest = published_at with id as tie-break.
 */
data class CurationQuery(
    val channelId: Long,
    val threshold: Int,
    val showUsed: Boolean = false,
    val search: String = "",
    val sort: CurationSort = CurationSort.Relevance,
    val limit: Int = 200,
) {
    fun sql(): String = buildString {
        append("SELECT channel_events.*, events.* FROM channel_events ")
        append("JOIN events ON events.id = channel_events.ce_event_id ")
        append("WHERE channel_events.ce_channel_id = ? AND channel_events.ce_score >= ?")
        if (!showUsed) append(" AND channel_events.ce_used = 0")
        if (search.isNotBlank()) append(" AND events.content LIKE ? ESCAPE '!'")
        append(" ORDER BY channel_events.ce_used ASC, ")
        append(
            when (sort) {
                CurationSort.Relevance -> "channel_events.ce_score DESC, events.publishedAtMillis DESC, channel_events.ce_id DESC"
                CurationSort.Newest -> "events.publishedAtMillis DESC, channel_events.ce_id DESC"
                CurationSort.Oldest -> "events.publishedAtMillis ASC, channel_events.ce_id ASC"
            },
        )
        append(" LIMIT ?")
    }

    fun args(): Array<Any> = buildList<Any> {
        add(channelId)
        add(threshold)
        if (search.isNotBlank()) add("%" + escapeLike(search.trim()) + "%")
        add(limit)
    }.toTypedArray()

    fun toSqlite() = SimpleSQLiteQuery(sql(), args())

    companion object {
        fun escapeLike(text: String): String =
            text.replace("!", "!!").replace("%", "!%").replace("_", "!_")
    }
}

/** The all-events list filters (EventsController#index), run locally. */
data class EventsQuery(
    val sourceId: Long? = null,
    val eventType: String? = null,
    val search: String = "",
    val limit: Int = 200,
) {
    fun sql(): String = buildString {
        append("SELECT * FROM events WHERE 1 = 1")
        if (sourceId != null) append(" AND sourceId = ?")
        if (!eventType.isNullOrBlank()) append(" AND eventType = ?")
        if (search.isNotBlank()) append(" AND content LIKE ? ESCAPE '!'")
        append(" ORDER BY publishedAtMillis DESC, id DESC LIMIT ?")
    }

    fun args(): Array<Any> = buildList<Any> {
        sourceId?.let { add(it) }
        if (!eventType.isNullOrBlank()) add(eventType)
        if (search.isNotBlank()) add("%" + CurationQuery.escapeLike(search.trim()) + "%")
        add(limit)
    }.toTypedArray()

    fun toSqlite() = SimpleSQLiteQuery(sql(), args())
}
