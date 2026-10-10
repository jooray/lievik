package today.cypherpunk.lievik.data.db

import androidx.room.ColumnInfo
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import kotlinx.serialization.builtins.ListSerializer
import today.cypherpunk.lievik.data.api.ApiJson
import today.cypherpunk.lievik.data.api.Author
import today.cypherpunk.lievik.data.api.Channel
import today.cypherpunk.lievik.data.api.ChannelContent
import today.cypherpunk.lievik.data.api.ChannelEvent
import today.cypherpunk.lievik.data.api.ChannelSettings
import today.cypherpunk.lievik.data.api.Event
import today.cypherpunk.lievik.data.api.Reference
import today.cypherpunk.lievik.data.api.Source
import today.cypherpunk.lievik.data.api.SourceSettings
import today.cypherpunk.lievik.data.api.TopChannel
import today.cypherpunk.lievik.util.Times

@Entity(tableName = "sources")
data class SourceEntity(
    @PrimaryKey val id: Long,
    val sourceType: String,
    val identifier: String?,
    val name: String?,
    val description: String?,
    val distance: Int,
    val includeReplies: Boolean,
    val includeReposts: Boolean,
    val importDays: Int,
    val eventCount: Int,
    val createdAt: String?,
    val updatedAt: String?,
) {
    fun toModel() = Source(
        id = id, sourceType = sourceType, identifier = identifier, name = name, description = description,
        distance = distance, settings = SourceSettings(includeReplies, includeReposts, importDays),
        eventCount = eventCount, createdAt = createdAt, updatedAt = updatedAt,
    )

    companion object {
        fun from(s: Source) = SourceEntity(
            s.id, s.sourceType, s.identifier, s.name, s.description, s.distance,
            s.settings.includeReplies, s.settings.includeReposts, s.settings.importDays,
            s.eventCount, s.createdAt, s.updatedAt,
        )
    }
}

@Entity(tableName = "channels")
data class ChannelEntity(
    @PrimaryKey val id: Long,
    val name: String,
    val description: String?,
    val language: String?,
    val prompt: String?,
    val contentPrompt: String?,
    val contentLanguage: String?,
    val contentStyle: String?,
    val relevanceThreshold: Int,
    val humanizeOutput: Boolean,
    val pendingCount: Int,
    val createdAt: String?,
    val updatedAt: String?,
) {
    fun toModel() = Channel(
        id = id, name = name, description = description, language = language, prompt = prompt,
        contentPrompt = contentPrompt, contentLanguage = contentLanguage, contentStyle = contentStyle,
        settings = ChannelSettings(relevanceThreshold, humanizeOutput), pendingCount = pendingCount,
        createdAt = createdAt, updatedAt = updatedAt,
    )

    companion object {
        fun from(c: Channel) = ChannelEntity(
            c.id, c.name, c.description, c.language, c.prompt, c.contentPrompt, c.contentLanguage, c.contentStyle,
            c.settings.relevanceThreshold, c.settings.humanizeOutput, c.pendingCount, c.createdAt, c.updatedAt,
        )
    }
}

/**
 * An event, flattened. Lists (images, references, top channels) are stored as
 * JSON text: they are only ever read back whole.
 */
@Entity(
    tableName = "events",
    indices = [Index("sourceId"), Index("publishedAtMillis")],
)
data class EventEntity(
    @PrimaryKey val id: Long,
    val sourceId: Long?,
    val sourceName: String?,
    val sourceType: String?,
    val externalId: String?,
    val eventType: String?,
    val kind: Int?,
    val content: String,
    val title: String?,
    val publishedAt: String?,
    val publishedAtMillis: Long,
    val updatedAt: String?,
    val authorName: String?,
    val authorPicture: String?,
    val authorNpub: String?,
    val sourceUrl: String?,
    val nostrUri: String? = null,
    val imagesJson: String,
    val referencesJson: String,
    val topChannelsJson: String,
) {
    fun toModel() = Event(
        id = id, sourceId = sourceId, sourceName = sourceName, sourceType = sourceType, externalId = externalId,
        eventType = eventType, kind = kind, content = content, title = title, publishedAt = publishedAt,
        updatedAt = updatedAt,
        author = if (authorName == null && authorPicture == null && authorNpub == null) null else Author(authorName, authorPicture, authorNpub),
        sourceUrl = sourceUrl,
        nostrUri = nostrUri,
        images = decode(imagesJson, ListSerializer(kotlinx.serialization.serializer<String>())),
        references = decode(referencesJson, ListSerializer(Reference.serializer())),
        topChannels = decode(topChannelsJson, ListSerializer(TopChannel.serializer())),
    )

    companion object {
        private fun <T> decode(text: String, s: kotlinx.serialization.KSerializer<List<T>>): List<T> =
            runCatching { ApiJson.decodeFromString(s, text) }.getOrDefault(emptyList())

        fun from(e: Event) = EventEntity(
            id = e.id, sourceId = e.sourceId, sourceName = e.sourceName, sourceType = e.sourceType,
            externalId = e.externalId, eventType = e.eventType, kind = e.kind, content = e.content, title = e.title,
            publishedAt = e.publishedAt, publishedAtMillis = Times.parseMillis(e.publishedAt) ?: 0L, updatedAt = e.updatedAt,
            authorName = e.author?.name, authorPicture = e.author?.pictureUrl, authorNpub = e.author?.npub,
            sourceUrl = e.sourceUrl,
            nostrUri = e.nostrUri,
            imagesJson = ApiJson.encodeToString(ListSerializer(kotlinx.serialization.serializer<String>()), e.images),
            referencesJson = ApiJson.encodeToString(ListSerializer(Reference.serializer()), e.references),
            topChannelsJson = ApiJson.encodeToString(ListSerializer(TopChannel.serializer()), e.topChannels),
        )
    }
}

/**
 * Columns carry a `ce_` prefix so a `SELECT channel_events.*, events.*` join
 * has no clashing names and maps straight onto [CurationRow].
 */
@Entity(
    tableName = "channel_events",
    indices = [Index(value = ["ce_channel_id", "ce_event_id"], unique = true), Index("ce_event_id")],
)
data class ChannelEventEntity(
    @PrimaryKey @ColumnInfo(name = "ce_id") val id: Long,
    @ColumnInfo(name = "ce_channel_id") val channelId: Long,
    @ColumnInfo(name = "ce_event_id") val eventId: Long,
    @ColumnInfo(name = "ce_score") val relevanceScore: Int?,
    @ColumnInfo(name = "ce_reason") val relevanceReason: String?,
    @ColumnInfo(name = "ce_used") val used: Boolean,
    @ColumnInfo(name = "ce_used_at") val usedAt: String?,
    @ColumnInfo(name = "ce_updated_at") val updatedAt: String?,
    @ColumnInfo(name = "ce_engine") val engine: String?,
) {
    fun toModel() = ChannelEvent(id, channelId, eventId, relevanceScore, relevanceReason, used, usedAt, updatedAt, engine)

    companion object {
        fun from(c: ChannelEvent) = ChannelEventEntity(
            c.id, c.channelId, c.eventId, c.relevanceScore, c.relevanceReason, c.used, c.usedAt, c.updatedAt, c.engine,
        )
    }
}

/** One curation-queue row: the rating and its event. */
data class CurationRow(
    @Embedded val channelEvent: ChannelEventEntity,
    @Embedded val event: EventEntity,
)

/** The content builder's lists, cached so drafts show offline. */
@Entity(tableName = "contents", indices = [Index("channelId")])
data class ContentEntity(
    @PrimaryKey val id: Long,
    val channelId: Long,
    val status: String,
    val title: String?,
    val updatedAt: String?,
    val json: String,
) {
    fun toModel(): ChannelContent = ApiJson.decodeFromString(ChannelContent.serializer(), json)

    companion object {
        fun from(c: ChannelContent) = ContentEntity(
            c.id, c.channelId, c.status, c.title, c.updatedAt, ApiJson.encodeToString(ChannelContent.serializer(), c),
        )
    }
}
