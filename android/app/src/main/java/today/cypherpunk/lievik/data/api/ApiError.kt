package today.cypherpunk.lievik.data.api

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import retrofit2.HttpException
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException

/**
 * Everything that can go wrong talking to the server, already sorted into what
 * the UI does about it. [serverMessage] is the server's own translated text
 * (it speaks the app's language) when it sent one.
 */
sealed class ApiError(open val serverMessage: String?) : Exception(serverMessage) {
    /** Token missing, revoked or expired: the app signs out to the login screen. */
    data class Unauthorized(override val serverMessage: String?) : ApiError(serverMessage)

    /** 402 paywall: no trial and no paid time. */
    data class Paywall(override val serverMessage: String?, val billingUrl: String?) : ApiError(serverMessage)

    /** 429 daily_cap: the daily safety cap for an AI feature. */
    data class DailyCap(override val serverMessage: String?) : ApiError(serverMessage)

    /** 503 billing_unavailable: billing is down and nothing cached says the user paid. */
    data class BillingUnavailable(override val serverMessage: String?) : ApiError(serverMessage)

    /** 422: form errors per field (`details`), or a named failure such as invalid_link / no_previous. */
    data class Validation(
        override val serverMessage: String?,
        val code: String?,
        val details: Map<String, List<String>> = emptyMap(),
    ) : ApiError(serverMessage) {
        /** All field messages, for a form without per-field slots. */
        val allMessages: List<String> get() = details.values.flatten()
    }

    /** 429 rate_limited (and login's per-IP limit). */
    data class RateLimited(override val serverMessage: String?, val retryAfterSeconds: Long?) : ApiError(serverMessage)

    data class NotFound(override val serverMessage: String?) : ApiError(serverMessage)

    /** 503 busy and similar named server refusals that are not billing. */
    data class Refused(val status: Int, val code: String?, override val serverMessage: String?) : ApiError(serverMessage)

    /** No connection, timeout, DNS failure. */
    data object Network : ApiError(null) {
        private fun readResolve(): Any = Network
    }

    /** 5xx, or a response the app could not read (an HTML proxy page). */
    data class Server(val status: Int, override val serverMessage: String?) : ApiError(serverMessage)

    val isBillingDenial: Boolean get() = this is Paywall || this is DailyCap || this is BillingUnavailable

    companion object {
        /** Maps an HTTP status + JSON error body (docs/API_V1.md "Errors") to an [ApiError]. */
        fun fromResponse(status: Int, body: String?, retryAfter: String? = null): ApiError {
            val json = body?.takeIf { it.isNotBlank() }?.let {
                runCatching { ApiJson.parseToJsonElement(it) as? JsonObject }.getOrNull()
            }
            val message = json?.get("error")?.let { (it as? JsonPrimitive)?.contentOrNull }
            val code = json?.get("code")?.let { (it as? JsonPrimitive)?.contentOrNull }
            val details = (json?.get("details") as? JsonObject)?.mapValues { (_, v) ->
                when (v) {
                    is JsonArray -> v.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
                    is JsonPrimitive -> listOfNotNull(v.contentOrNull)
                    else -> emptyList()
                }
            } ?: emptyMap()
            return when {
                status == 401 -> Unauthorized(message)
                status == 402 || code == "paywall" -> Paywall(message, json?.get("billing_url")?.jsonPrimitive?.contentOrNull)
                code == "daily_cap" -> DailyCap(message)
                code == "billing_unavailable" -> BillingUnavailable(message)
                status == 429 -> RateLimited(message, retryAfter?.trim()?.toLongOrNull())
                status == 404 -> NotFound(message)
                status == 422 || status == 400 -> Validation(message, code, details)
                status in 500..599 && code != null -> Refused(status, code, message)
                status >= 500 -> Server(status, message)
                code != null -> Refused(status, code, message)
                else -> Server(status, message)
            }
        }

        /** Any failure from a call → [ApiError]. Cancellation is rethrown, never mapped. */
        fun from(t: Throwable): ApiError = when (t) {
            is CancellationException -> throw t
            is ApiError -> t
            is HttpException -> {
                val response = t.response()
                val body = runCatching { response?.errorBody()?.string() }.getOrNull()
                fromResponse(t.code(), body, response?.headers()?.get("Retry-After"))
            }
            is IOException -> Network
            is SerializationException -> Server(200, null)
            is IllegalArgumentException -> Server(200, null)
            else -> Server(0, null)
        }
    }
}

/** Runs [block], turning every failure into an [ApiError] result. */
suspend fun <T> apiCall(block: suspend () -> T): Result<T> = try {
    Result.success(block())
} catch (e: CancellationException) {
    throw e
} catch (e: Throwable) {
    Result.failure(ApiError.from(e))
}
