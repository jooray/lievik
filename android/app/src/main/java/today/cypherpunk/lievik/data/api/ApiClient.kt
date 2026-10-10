package today.cypherpunk.lievik.data.api

import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.serialization.json.JsonElement
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * HTTP plumbing for the API. The server URL can change at runtime (self-hosted
 * instances), so Retrofit is built against a placeholder host and
 * [ServerRewrite] points every request at the current server.
 */
class ApiClient(
    private val serverUrl: () -> String,
    private val token: () -> String?,
    private val language: () -> String,
    private val userAgent: String,
    private val onUnauthorized: () -> Unit,
) {
    private val placeholder = "http://lievik.invalid/api/v1/".toHttpUrl()

    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .addInterceptor(ServerRewrite())
        .addInterceptor(Headers())
        .build()

    val api: LievikApi = Retrofit.Builder()
        .baseUrl(placeholder)
        .client(http)
        .addConverterFactory(ApiJson.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(LievikApi::class.java)

    /** The AI streams run for minutes; only the stream client waits that long. */
    private val streamHttp: OkHttpClient = http.newBuilder()
        .readTimeout(5, TimeUnit.MINUTES)
        .build()

    private inner class ServerRewrite : Interceptor {
        override fun intercept(chain: Interceptor.Chain): Response {
            val request = chain.request()
            val url = request.url
            if (url.host != placeholder.host) return chain.proceed(request)
            val base = apiBase(serverUrl()) ?: throw IOException("invalid server url")
            val rest = url.encodedPath.removePrefix(placeholder.encodedPath)
            val target = base.newBuilder().addEncodedPathSegments(rest).encodedQuery(url.encodedQuery).build()
            return chain.proceed(request.newBuilder().url(target).build())
        }
    }

    private inner class Headers : Interceptor {
        override fun intercept(chain: Interceptor.Chain): Response {
            val builder = chain.request().newBuilder()
                .header("Accept-Language", language())
                .header("User-Agent", userAgent)
            if (chain.request().header("Accept") == null) builder.header("Accept", "application/json")
            val bearer = token()
            if (bearer != null) builder.header("Authorization", "Bearer $bearer")
            val response = chain.proceed(builder.build())
            // Only a rejected token signs out: a 401 from /auth/token (bad
            // signature) is a failed login, not a lost session.
            if (response.code == 401 && bearer != null) onUnauthorized()
            return response
        }
    }

    /**
     * POST [path] with a JSON [body] and read the reply as server-sent events
     * (docs/API_V1.md "Server-sent events"). Billing denials and other errors
     * arrive as a JSON error before any event and end the flow with an
     * [ApiError]. Cancelling the collector cancels the HTTP call, so the server
     * stops generating (and spending) at once.
     */
    fun stream(path: String, body: JsonElement): Flow<StreamEvent> = callbackFlow {
        val request = Request.Builder()
            .url(placeholder.newBuilder().addEncodedPathSegments(path).build())
            .header("Accept", "text/event-stream")
            .post(ApiJson.encodeToString(JsonElement.serializer(), body).toRequestBody("application/json".toMediaType()))
            .build()
        val listener = object : EventSourceListener() {
            override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                StreamEvents.decode(type, data)?.let { trySend(it) }
            }

            override fun onClosed(eventSource: EventSource) {
                close()
            }

            override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                val error = when {
                    response != null && !response.isSuccessful ->
                        ApiError.fromResponse(response.code, runCatching { response.body.string() }.getOrNull(), response.header("Retry-After"))
                    t != null -> ApiError.from(t)
                    else -> ApiError.Server(response?.code ?: 0, null)
                }
                close(error)
            }
        }
        val source = EventSources.createFactory(streamHttp).newEventSource(request, listener)
        awaitClose { source.cancel() }
    }

    companion object {
        /** `https://host[/prefix]` → `https://host[/prefix]/api/v1/`, or null when not a URL. */
        fun apiBase(server: String): HttpUrl? {
            val trimmed = server.trim().trimEnd('/')
            val url = trimmed.toHttpUrlOrNull() ?: return null
            return url.newBuilder().addPathSegments("api/v1/").build()
        }
    }
}
