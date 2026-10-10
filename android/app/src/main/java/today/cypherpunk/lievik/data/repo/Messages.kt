package today.cypherpunk.lievik.data.repo

import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError

/** Something to tell the user once: a snackbar, or the billing dialog. */
sealed interface UiMessage {
    data class Text(val text: String) : UiMessage
    data class Res(@StringRes val id: Int, val args: List<Any> = emptyList()) : UiMessage
    data class Plural(@PluralsRes val id: Int, val count: Int, val args: List<Any> = emptyList()) : UiMessage

    /** 402 / 429 daily_cap / 503 billing_unavailable — shown as a dialog offering "Go to billing". */
    data class BillingDenial(val error: ApiError) : UiMessage
}

/**
 * The app-wide message bus. Every screen reports failures here, so billing
 * denials and errors look the same everywhere.
 */
class Messages {
    private val _flow = MutableSharedFlow<UiMessage>(extraBufferCapacity = 16, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val flow: SharedFlow<UiMessage> = _flow

    fun show(message: UiMessage) {
        _flow.tryEmit(message)
    }

    fun text(text: String?) {
        if (!text.isNullOrBlank()) show(UiMessage.Text(text))
    }

    fun res(@StringRes id: Int, vararg args: Any) = show(UiMessage.Res(id, args.toList()))

    /** A failure → the message the user sees. Sign-out on 401 happens in the HTTP layer. */
    fun error(t: Throwable) {
        val error = ApiError.from(t)
        show(forError(error))
    }

    companion object {
        fun forError(error: ApiError): UiMessage = when (error) {
            is ApiError.Paywall, is ApiError.DailyCap, is ApiError.BillingUnavailable -> UiMessage.BillingDenial(error)
            is ApiError.Network -> UiMessage.Res(R.string.error_network)
            is ApiError.Unauthorized -> UiMessage.Res(R.string.error_session_ended)
            is ApiError.Validation -> error.serverMessage?.let { UiMessage.Text(it) }
                ?: error.allMessages.firstOrNull()?.let { UiMessage.Text(it) }
                ?: UiMessage.Res(R.string.error_unknown)
            is ApiError.RateLimited -> error.serverMessage?.let { UiMessage.Text(it) } ?: UiMessage.Res(R.string.error_rate_limited)
            is ApiError.Server -> error.serverMessage?.let { UiMessage.Text(it) }
                ?: if (error.status == 200) UiMessage.Res(R.string.error_unexpected) else UiMessage.Res(R.string.error_server, listOf(error.status))
            else -> error.serverMessage?.let { UiMessage.Text(it) } ?: UiMessage.Res(R.string.error_unknown)
        }

        /** The default text for a billing denial when the server sent none (the web's wording). */
        @StringRes
        fun denialText(error: ApiError): Int = when (error) {
            is ApiError.DailyCap -> R.string.billing_daily_cap
            is ApiError.BillingUnavailable -> R.string.billing_unavailable
            else -> R.string.billing_paywall
        }
    }
}
