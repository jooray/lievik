package today.cypherpunk.lievik.data.api

import kotlinx.serialization.json.JsonObject
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.nostrsignin.Challenge
import today.cypherpunk.nostrsignin.ConnectSession
import today.cypherpunk.nostrsignin.PollResult
import today.cypherpunk.nostrsignin.SignInBackend

/**
 * The shared sign-in module (android/nostr-signin) over Lievik's API. Failures
 * surface as [ApiError] so the login screen renders them like any other.
 */
class LievikSignInBackend(private val container: AppContainer) : SignInBackend {
    private val api get() = container.api

    override suspend fun challenge(): Challenge {
        val challenge = call { api.challenge() }
        return Challenge(challenge.challenge, challenge.domain, challenge.tokenUrl)
    }

    override suspend fun exchangeSignedEvent(signedEventJson: String) {
        val event = ApiJson.parseToJsonElement(signedEventJson) as JsonObject
        val response = call { api.token(TokenRequest(event, container.deviceName)) }
        container.signedIn(response.token, response.user)
    }

    override suspend fun startNostrConnect(): ConnectSession =
        call { api.nostrconnect() }.let { ConnectSession(it.sessionId, it.pollToken, it.uri) }

    override suspend fun startBunker(bunkerUri: String): ConnectSession =
        call { api.bunker(BunkerRequest(bunkerUri)) }.let { ConnectSession(it.sessionId, it.pollToken, null) }

    override suspend fun poll(session: ConnectSession): PollResult {
        val response = call { api.poll(PollRequest(session.sessionId, session.pollToken.orEmpty(), container.deviceName)) }
        return when (response.status) {
            "authenticated" -> {
                val token = response.token ?: return PollResult.Expired
                container.signedIn(token, response.user)
                PollResult.Authenticated
            }
            "expired" -> PollResult.Expired
            else -> PollResult.Pending(response.authUrl)
        }
    }

    override fun isTransient(error: Throwable) = error is ApiError.Network || error is ApiError.RateLimited

    private suspend fun <T> call(block: suspend () -> T): T = apiCall(block).getOrThrow()
}
