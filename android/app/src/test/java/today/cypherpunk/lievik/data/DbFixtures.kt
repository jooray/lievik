package today.cypherpunk.lievik.data

import today.cypherpunk.lievik.data.db.ChannelEntity
import today.cypherpunk.lievik.data.db.ChannelEventEntity
import today.cypherpunk.lievik.data.db.EventEntity
import today.cypherpunk.lievik.data.db.SourceEntity

object DbFixtures {
    fun source(id: Long, type: String = "nostr") =
        SourceEntity(id, type, "npub$id", "Source $id", null, 5, false, false, 30, 0, null, null)

    fun channel(id: Long, threshold: Int = 50) =
        ChannelEntity(id, "Channel $id", null, "en", "criteria", null, null, null, threshold, true, 0, null, null)

    fun event(id: Long, sourceId: Long, content: String = "event $id", publishedAt: Long = id * 1000) = EventEntity(
        id = id, sourceId = sourceId, sourceName = "Source $sourceId", sourceType = "nostr", externalId = "ext$id",
        eventType = "original", kind = 1, content = content, title = null, publishedAt = null,
        publishedAtMillis = publishedAt, updatedAt = null, authorName = null, authorPicture = null, authorNpub = null,
        sourceUrl = null, imagesJson = "[]", referencesJson = "[]", topChannelsJson = "[]",
    )

    fun rating(id: Long, channelId: Long, eventId: Long, score: Int?, used: Boolean = false) =
        ChannelEventEntity(id, channelId, eventId, score, "reason $id", used, null, null, "chat")
}
