package today.cypherpunk.lievik.data.db

/**
 * The pure part of applying a /sync page.
 *
 * A source or channel is "removed" only if this device knew it and the server
 * no longer lists it. Deleting "everything not in the list" instead would also
 * wipe events whose source the list never contains (the manual-entries
 * source, which the web hides from source lists).
 */
object SyncMerge {
    fun removed(local: Collection<Long>, remote: Collection<Long>): List<Long> {
        val keep = remote.toHashSet()
        return local.filterNot { it in keep }.distinct()
    }

    fun keepEvents(events: List<EventEntity>, removedSources: Collection<Long>): List<EventEntity> {
        if (removedSources.isEmpty()) return events
        val gone = removedSources.toHashSet()
        return events.filterNot { it.sourceId != null && it.sourceId in gone }
    }

    fun keepChannelEvents(rows: List<ChannelEventEntity>, removedChannels: Collection<Long>): List<ChannelEventEntity> {
        if (removedChannels.isEmpty()) return rows
        val gone = removedChannels.toHashSet()
        return rows.filterNot { it.channelId in gone }
    }
}
