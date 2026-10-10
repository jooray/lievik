package today.cypherpunk.lievik.data.api

import kotlinx.serialization.json.JsonObject
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/** docs/API_V1.md, one method per endpoint. Paths are relative to `<server>/api/v1/`. */
interface LievikApi {
    @GET("meta") suspend fun meta(): Meta

    // auth
    @POST("auth/challenge") suspend fun challenge(@Body body: JsonObject = JsonObject(emptyMap())): Challenge
    @POST("auth/token") suspend fun token(@Body body: TokenRequest): TokenResponse
    @POST("auth/nostrconnect") suspend fun nostrconnect(@Body body: JsonObject = JsonObject(emptyMap())): Nip46Session
    @POST("auth/bunker") suspend fun bunker(@Body body: BunkerRequest): Nip46Session
    @POST("auth/poll") suspend fun poll(@Body body: PollRequest): PollResponse
    @DELETE("session") suspend fun signOut(): Response<Unit>

    // me
    @GET("me") suspend fun me(): MeResponse
    @PATCH("me") suspend fun updateMe(@Body body: UserUpdate): UserResponse
    @POST("me/refresh_profile") suspend fun refreshProfile(): Notice
    @POST("me/reindex") suspend fun reindex(): Notice

    @GET("templates") suspend fun templates(): TemplatesResponse
    @POST("templates") suspend fun createTemplate(@Body body: TemplateBody): Notice
    @PATCH("templates/{index}") suspend fun updateTemplate(@Path("index") index: Int, @Body body: TemplateBody): Notice
    @DELETE("templates/{index}") suspend fun deleteTemplate(@Path("index") index: Int): Notice

    @GET("api_tokens") suspend fun apiTokens(): ApiTokensResponse
    @POST("api_tokens") suspend fun createApiToken(@Body body: NameBody): ApiTokenCreated
    @DELETE("api_tokens/{id}") suspend fun revokeApiToken(@Path("id") id: Long): Notice

    // dashboard / sync
    @GET("dashboard") suspend fun dashboard(): DashboardResponse
    @POST("dashboard/rate_all") suspend fun rateAll(): Notice
    @GET("sync") suspend fun sync(@Query("since") since: String?, @Query("cursor") cursor: String?): SyncResponse

    // sources
    @GET("sources") suspend fun sources(): SourcesResponse
    @GET("sources/{id}") suspend fun source(@Path("id") id: Long): SourceResponse
    @GET("sources/{id}/events") suspend fun sourceEvents(@Path("id") id: Long, @Query("page") page: Int): EventsResponse
    @POST("sources") suspend fun createSource(@Body body: SourceBody): SourceResponse
    @PATCH("sources/{id}") suspend fun updateSource(@Path("id") id: Long, @Body body: SourceBody): SourceResponse
    @DELETE("sources/{id}") suspend fun deleteSource(@Path("id") id: Long): Notice
    @POST("sources/{id}/refresh") suspend fun refreshSource(@Path("id") id: Long): Notice
    @POST("sources/refresh_all") suspend fun refreshAllSources(): Notice

    // channels
    @GET("channels") suspend fun channels(): ChannelsResponse
    @GET("channels/new") suspend fun newChannel(): ChannelResponse
    @GET("channels/{id}") suspend fun channel(@Path("id") id: Long): ChannelResponse
    @POST("channels") suspend fun createChannel(@Body body: ChannelBody): ChannelResponse
    @PATCH("channels/{id}") suspend fun updateChannel(@Path("id") id: Long, @Body body: ChannelBody): ChannelResponse
    @DELETE("channels/{id}") suspend fun deleteChannel(@Path("id") id: Long): Notice
    @POST("channels/{id}/rate") suspend fun rateChannel(@Path("id") id: Long): Notice

    @GET("channels/{id}/events") suspend fun channelEvents(
        @Path("id") id: Long,
        @Query("show_used") showUsed: Boolean?,
        @Query("search") search: String?,
        @Query("sort") sort: String?,
        @Query("page") page: Int,
        @Query("per") per: Int?,
    ): ChannelEventsResponse
    @POST("channels/{id}/events/mark_used") suspend fun markUsed(@Path("id") id: Long, @Body body: EventIdsBody): Notice
    @POST("channels/{id}/events/mark_unused") suspend fun markUnused(@Path("id") id: Long, @Body body: EventIdsBody): Notice
    @POST("channels/{id}/events/rate") suspend fun rateChannelEvents(@Path("id") id: Long, @Body body: EventIdsBody): Notice

    // content builder
    @GET("channels/{cid}/contents") suspend fun contents(@Path("cid") channelId: Long): ContentsResponse
    @GET("channels/{cid}/contents/{id}") suspend fun content(@Path("cid") channelId: Long, @Path("id") id: Long): ContentResponse
    @POST("channels/{cid}/contents") suspend fun createContent(@Path("cid") channelId: Long, @Body body: ContentCreateBody): ContentResponse
    @PATCH("channels/{cid}/contents/{id}") suspend fun updateContent(@Path("cid") channelId: Long, @Path("id") id: Long, @Body body: ContentUpdateBody): ContentResponse
    @DELETE("channels/{cid}/contents/{id}") suspend fun deleteContent(@Path("cid") channelId: Long, @Path("id") id: Long): Notice
    @POST("channels/{cid}/contents/{id}/publish") suspend fun publishContent(@Path("cid") channelId: Long, @Path("id") id: Long): ContentResponse
    @POST("channels/{cid}/contents/{id}/revert") suspend fun revertContent(@Path("cid") channelId: Long, @Path("id") id: Long): ContentResponse

    // events
    @GET("events") suspend fun events(
        @Query("source_id") sourceId: Long?,
        @Query("event_type") eventType: String?,
        @Query("search") search: String?,
        @Query("page") page: Int,
    ): EventsResponse
    @GET("events/{id}") suspend fun event(@Path("id") id: Long): EventDetailResponse
    @POST("events/rate") suspend fun rateEvents(@Body body: RateEventsBody): Notice
    @POST("events/{id}/mark_used") suspend fun markEventUsed(@Path("id") id: Long, @Body body: ChannelEventIdsBody): Notice
    @POST("manual_events") suspend fun createManualEvent(@Body body: ManualEventBody): EventResponse

    // ask
    @GET("chat") suspend fun chatInfo(): ChatInfo

    // AI channels
    @POST("channels/ai/bulk_create") suspend fun bulkCreateChannels(@Body body: BulkCreateBody): Notice

    // activity
    @GET("activity_logs") suspend fun activityLogs(@Query("page") page: Int): ActivityLogsResponse
    @GET("activity_logs/active") suspend fun activeJobs(): ActiveJobsResponse
    @GET("activity_logs/{id}/dev_logs") suspend fun devLogs(@Path("id") id: Long, @Query("page") page: Int): DevLogsResponse
    @POST("activity_logs/{id}/cancel") suspend fun cancelJob(@Path("id") id: Long): Notice
    @POST("activity_logs/{id}/retry") suspend fun retryJob(@Path("id") id: Long): Notice
    @POST("activity_logs/cleanup_stale") suspend fun cleanupStale(): Notice

    // billing
    @GET("billing") suspend fun billing(): BillingResponse
    @POST("billing/trial") suspend fun startTrial(): BillingTrialResponse
    @POST("billing/charges") suspend fun createCharge(@Body body: ChargeBody): Charge
    @GET("billing/charges/{invoice}") suspend fun charge(@Path("invoice") invoiceId: String): ChargeStatus
}
