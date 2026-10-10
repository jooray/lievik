@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package today.cypherpunk.lievik.data.api

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNamingStrategy
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * The one JSON configuration for the API (docs/API_V1.md): snake_case on the
 * wire, unknown keys ignored so a newer server never breaks an older app.
 */
val ApiJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
    coerceInputValues = true
    isLenient = true
    namingStrategy = JsonNamingStrategy.SnakeCase
}

// ---------------------------------------------------------------- meta / auth

@Serializable
data class Meta(
    val apiVersion: Int = 1,
    val buildVersion: String? = null,
    val instanceName: String? = null,
    val billingEnabled: Boolean = false,
    val decisionRatingAvailable: Boolean = false,
    val locales: List<String> = emptyList(),
    val android: AndroidMeta? = null,
    val nip46Relays: List<String> = emptyList(),
)

@Serializable
data class AndroidMeta(
    val minVersionCode: Int = 1,
    val latestVersionCode: Int = 1,
    val downloadUrl: String? = null,
)

@Serializable
data class Challenge(val challenge: String, val domain: String, val tokenUrl: String? = null, val expiresIn: Int = 300)

@Serializable
data class TokenRequest(val signedEvent: JsonObject, val deviceName: String)

@Serializable
data class TokenResponse(val token: String, val user: User? = null)

@Serializable
data class Nip46Session(
    val sessionId: String,
    val pollToken: String,
    val uri: String? = null,
    val expiresAt: String? = null,
)

@Serializable
data class BunkerRequest(val bunkerUri: String)

@Serializable
data class PollRequest(val sessionId: String, val pollToken: String, val deviceName: String)

@Serializable
data class PollResponse(
    val status: String,
    val authUrl: String? = null,
    val token: String? = null,
    val user: User? = null,
)

// ---------------------------------------------------------------- user

@Serializable
data class User(
    val id: Long = 0,
    val npub: String = "",
    val pubkeyHex: String = "",
    val displayName: String? = null,
    val username: String? = null,
    val about: String? = null,
    val pictureUrl: String? = null,
    val settings: UserSettings = UserSettings(),
) {
    val label: String get() = displayName?.takeIf { it.isNotBlank() } ?: username?.takeIf { it.isNotBlank() } ?: npub.take(16)
}

@Serializable
data class UserSettings(
    val locale: String? = null,
    val ratingEngine: String? = null,
    val eventLinkTemplate: String? = null,
    val naddrLinkTemplate: String? = null,
    val profileLinkTemplate: String? = null,
    val systemPrompt: String? = null,
    val defaultContentStyle: String? = null,
)

@Serializable
data class Stats(
    val sources: Int = 0,
    val channels: Int = 0,
    val events: Int = 0,
    val embedded: Int = 0,
)

@Serializable
data class MeResponse(val user: User, val stats: Stats? = null, val billing: BillingStatus? = null)

@Serializable
data class UserUpdate(val user: Map<String, String?>)

@Serializable
data class UserResponse(val user: User? = null, val notice: String? = null)

@Serializable
data class Notice(val notice: String? = null, val count: Int? = null, val queuedChannels: Int? = null)

// ---------------------------------------------------------------- templates / tokens

@Serializable
data class ContentTemplate(val index: Int = -1, val name: String = "", val template: String = "")

@Serializable
data class TemplatesResponse(val templates: List<ContentTemplate> = emptyList(), val defaults: List<ContentTemplate> = emptyList())

@Serializable
data class TemplateBody(val name: String, val template: String)

@Serializable
data class ApiToken(
    val id: Long,
    val name: String = "",
    val preview: String? = null,
    val createdAt: String? = null,
    val lastUsedAt: String? = null,
    val expiresAt: String? = null,
    val current: Boolean = false,
)

@Serializable
data class ApiTokensResponse(val apiTokens: List<ApiToken> = emptyList())

@Serializable
data class NameBody(val name: String)

@Serializable
data class ApiTokenCreated(val apiToken: ApiToken? = null, val plainToken: String)

// ---------------------------------------------------------------- core records

@Serializable
data class SourceSettings(
    val includeReplies: Boolean = false,
    val includeReposts: Boolean = false,
    val importDays: Int = 30,
)

@Serializable
data class Source(
    val id: Long = 0,
    val sourceType: String = "nostr",
    val identifier: String? = null,
    val name: String? = null,
    val description: String? = null,
    val distance: Int = 5,
    val settings: SourceSettings = SourceSettings(),
    val eventCount: Int = 0,
    val createdAt: String? = null,
    val updatedAt: String? = null,
)

@Serializable
data class ChannelSettings(
    val relevanceThreshold: Int = 50,
    val humanizeOutput: Boolean = true,
)

@Serializable
data class Channel(
    val id: Long = 0,
    val name: String = "",
    val description: String? = null,
    val language: String? = null,
    val prompt: String? = null,
    val contentPrompt: String? = null,
    val contentLanguage: String? = null,
    val contentStyle: String? = null,
    val settings: ChannelSettings = ChannelSettings(),
    val pendingCount: Int = 0,
    val createdAt: String? = null,
    val updatedAt: String? = null,
)

@Serializable
data class Author(val name: String? = null, val pictureUrl: String? = null, val npub: String? = null)

@Serializable
data class Reference(
    val uri: String,
    val type: String = "profile",
    val label: String? = null,
    val preview: String? = null,
    val url: String? = null,
    val npub: String? = null,
)

@Serializable
data class TopChannel(
    val channelId: Long,
    val channelName: String? = null,
    val relevanceScore: Int? = null,
    val used: Boolean = false,
)

@Serializable
data class Event(
    val id: Long,
    val sourceId: Long? = null,
    val sourceName: String? = null,
    val sourceType: String? = null,
    val externalId: String? = null,
    val eventType: String? = null,
    val kind: Int? = null,
    val content: String = "",
    val title: String? = null,
    val publishedAt: String? = null,
    val updatedAt: String? = null,
    val author: Author? = null,
    val sourceUrl: String? = null,
    val nostrUri: String? = null,
    val images: List<String> = emptyList(),
    val references: List<Reference> = emptyList(),
    val topChannels: List<TopChannel> = emptyList(),
)

@Serializable
data class ChannelEvent(
    val id: Long,
    val channelId: Long,
    val eventId: Long,
    val relevanceScore: Int? = null,
    val relevanceReason: String? = null,
    val used: Boolean = false,
    val usedAt: String? = null,
    val updatedAt: String? = null,
    val engine: String? = null,
    val channelName: String? = null,
)

@Serializable
data class ActivityLog(
    val id: Long,
    val activityType: String? = null,
    val status: String? = null,
    val message: String? = null,
    val progress: JsonElement? = null,
    val metadata: JsonObject? = null,
    val createdAt: String? = null,
    val updatedAt: String? = null,
    val completedAt: String? = null,
    val devLogCount: Int = 0,
    val stale: Boolean = false,
) {
    /**
     * Progress as a percentage, or null when the job reports none. The contract
     * leaves the shape open, so a number, a {current,total} object and the
     * web's metadata.progress are all accepted.
     */
    val percent: Int?
        get() {
            fun fromObject(o: JsonObject?): Int? {
                val total = o?.get("total")?.jsonPrimitive?.intOrNull ?: return null
                val current = o["current"]?.jsonPrimitive?.intOrNull ?: 0
                return if (total == 0) 0 else (current * 100 / total).coerceIn(0, 100)
            }
            val p = progress
            if (p is kotlinx.serialization.json.JsonPrimitive) p.intOrNull?.let { return it.coerceIn(0, 100) }
            if (p is JsonObject) fromObject(p)?.let { return it }
            return fromObject(metadata?.get("progress") as? JsonObject)
        }

    val channelId: Long?
        get() = metadata?.get("channel_id")?.jsonPrimitive?.contentOrNull?.toLongOrNull()

    val isActive: Boolean get() = status == "pending" || status == "running"
}

@Serializable
data class DevLog(
    val id: Long,
    val logType: String? = null,
    val message: String? = null,
    val details: JsonElement? = null,
    val createdAt: String? = null,
) {
    fun detail(key: String): String? = (details as? JsonObject)?.get(key)?.let {
        (it as? kotlinx.serialization.json.JsonPrimitive)?.contentOrNull ?: it.toString()
    }
}

@Serializable
data class ChannelContent(
    val id: Long,
    val channelId: Long = 0,
    val title: String? = null,
    val content: String? = null,
    val generationPrompt: String? = null,
    val status: String = "draft",
    val publishedAt: String? = null,
    val eventIds: List<Long> = emptyList(),
    val versionsCount: Int = 0,
    val createdAt: String? = null,
    val updatedAt: String? = null,
)

@Serializable
data class OtherProduct(val product: String, val state: String? = null, val until: String? = null)

@Serializable
data class BillingStatus(
    val enabled: Boolean = false,
    val state: String = "unknown",
    val allows: Boolean = true,
    val until: String? = null,
    val otherProducts: List<OtherProduct> = emptyList(),
    val npub: String? = null,
)

// ---------------------------------------------------------------- responses

@Serializable
data class PageMeta(val page: Int = 1, val per: Int = 50, val totalPages: Int = 1, val totalCount: Int = 0)

@Serializable
data class DashboardResponse(
    val stats: Stats = Stats(),
    val activeJobs: List<ActivityLog> = emptyList(),
    val recentEvents: List<Event> = emptyList(),
)

@Serializable
data class SyncResponse(
    val serverTime: String,
    val sources: List<Source> = emptyList(),
    val channels: List<Channel> = emptyList(),
    val events: List<Event> = emptyList(),
    val channelEvents: List<ChannelEvent> = emptyList(),
    val nextCursor: String? = null,
)

@Serializable
data class SourcesResponse(val sources: List<Source> = emptyList())

@Serializable
data class SourceResponse(val source: Source? = null, val notice: String? = null, val importing: Boolean = false)

@Serializable
data class SourceBody(val source: SourceForm)

@Serializable
data class SourceForm(
    val sourceType: String,
    val identifier: String,
    val name: String,
    val description: String,
    val distance: Int,
    val settingsIncludeReplies: Boolean,
    val settingsIncludeReposts: Boolean,
    val settingsImportDays: Int,
)

@Serializable
data class EventsResponse(
    val events: List<Event> = emptyList(),
    val meta: PageMeta = PageMeta(),
    val filterSources: List<FilterSource> = emptyList(),
)

@Serializable
data class FilterSource(val id: Long, val name: String? = null, val sourceType: String? = null)

@Serializable
data class ChannelsResponse(val channels: List<Channel> = emptyList())

@Serializable
data class ChannelResponse(
    val channel: Channel? = null,
    val usedCount: Int = 0,
    val unusedCount: Int = 0,
    val defaultPromptTemplate: String? = null,
    val notice: String? = null,
    val queued: Int? = null,
)

@Serializable
data class ChannelBody(val channel: ChannelForm)

@Serializable
data class ChannelForm(
    val name: String? = null,
    val description: String? = null,
    val language: String? = null,
    val prompt: String? = null,
    val contentPrompt: String? = null,
    val contentLanguage: String? = null,
    val contentStyle: String? = null,
    val settings: ChannelSettings? = null,
)

@Serializable
data class CurationItem(val channelEvent: ChannelEvent, val event: Event)

@Serializable
data class ChannelEventsResponse(
    val items: List<CurationItem> = emptyList(),
    val meta: PageMeta = PageMeta(),
    val usedCount: Int = 0,
    val unusedCount: Int = 0,
    val threshold: Int = 50,
)

@Serializable
data class EventIdsBody(val eventIds: List<Long>)

@Serializable
data class ChannelEventIdsBody(val channelEventIds: List<Long>)

@Serializable
data class RateEventsBody(
    val eventIds: List<Long>? = null,
    val sourceId: Long? = null,
    val eventType: String? = null,
    val search: String? = null,
)

@Serializable
data class ContentsResponse(val drafts: List<ChannelContent> = emptyList(), val published: List<ChannelContent> = emptyList())

@Serializable
data class ContentResponse(val content: ChannelContent? = null, val events: List<Event> = emptyList(), val notice: String? = null)

@Serializable
data class ContentCreateBody(val channelContent: ContentForm, val eventIds: List<Long>)

@Serializable
data class ContentUpdateBody(val channelContent: ContentForm)

@Serializable
data class ContentForm(val title: String? = null, val content: String? = null, val generationPrompt: String? = null)

@Serializable
data class LinkedContent(val url: String, val title: String? = null, val summary: String? = null, val fetchedAt: String? = null)

@Serializable
data class EventDetailResponse(
    val event: Event,
    val channelEvents: List<ChannelEvent> = emptyList(),
    val linkedContents: List<LinkedContent> = emptyList(),
)

@Serializable
data class ManualEventBody(val content: String)

@Serializable
data class EventResponse(val event: Event? = null, val notice: String? = null)

@Serializable
data class ChatInfo(val embeddedCount: Int = 0, val totalCount: Int = 0)

@Serializable
data class ChatTurn(val role: String, val content: String)

@Serializable
data class CitedEvent(val id: Long, val content: String? = null, val sourceName: String? = null, val publishedAt: String? = null)

@Serializable
data class ProposalChannel(
    val name: String = "",
    val description: String? = null,
    val language: String? = null,
    val prompt: String? = null,
    val contentStyle: String? = null,
    val contentLanguage: String? = null,
    val suggestedTemplate: String? = null,
    val settings: ChannelSettings = ChannelSettings(),
)

@Serializable
data class Proposal(val channels: List<ProposalChannel> = emptyList(), val templates: List<TemplateBody> = emptyList())

@Serializable
data class BulkCreateBody(val channels: List<ProposalChannel>, val templates: List<TemplateBody>)

@Serializable
data class ActivityLogsResponse(
    val activityLogs: List<ActivityLog> = emptyList(),
    val meta: PageMeta = PageMeta(),
    val active: List<ActivityLog> = emptyList(),
    val staleCount: Int = 0,
)

@Serializable
data class ActiveJobsResponse(val active: Boolean = false, val jobs: List<ActivityLog> = emptyList())

@Serializable
data class DevLogsResponse(val devLogs: List<DevLog> = emptyList(), val meta: PageMeta = PageMeta())

@Serializable
data class Plan(val plan: String, val sats: Long, val days: Int)

@Serializable
data class PendingCharge(val invoiceId: String, val plan: String? = null, val checkoutUrl: String? = null)

@Serializable
data class BillingResponse(
    val status: BillingStatus = BillingStatus(),
    val plans: List<Plan> = emptyList(),
    val minSats: Long = 1000,
    val maxSats: Long = 1_000_000,
    val pendingCharges: List<PendingCharge> = emptyList(),
    val notice: String? = null,
)

@Serializable
data class BillingTrialResponse(val status: BillingStatus? = null, val notice: String? = null)

@Serializable
data class ChargeBody(val plan: String, val sats: Long? = null)

@Serializable
data class Charge(val invoiceId: String, val checkoutUrl: String)

@Serializable
data class ChargeStatus(val settled: Boolean = false, val status: BillingStatus? = null, val notice: String? = null)

/** Reads the `"error"` text out of an SSE error payload or a JSON error body. */
fun JsonElement.errorMessage(): String? = runCatching {
    jsonObject["message"]?.jsonPrimitive?.contentOrNull ?: jsonObject["error"]?.jsonPrimitive?.contentOrNull
}.getOrNull()
