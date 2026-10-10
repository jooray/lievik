package today.cypherpunk.lievik.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.BillingStatus
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.repo.Messages
import today.cypherpunk.lievik.util.Times

/** Billing is shown only when the server has it on (meta.billing_enabled) and says so for this user. */
@Composable
fun billingEnabled(): Boolean {
    val container = LocalContainer.current
    val meta by container.meta.collectAsState()
    val me by container.me.collectAsState()
    return meta?.billingEnabled == true && me?.billing?.enabled != false
}

/**
 * The web's billing-status banner (billing/status.html.erb): silent for a
 * paying user and while billing cannot be reached; otherwise trial, expired or
 * not-started, with "Start free trial" for the latter.
 */
@Composable
fun BillingBanner(onOpenBilling: () -> Unit, modifier: Modifier = Modifier) {
    val container = LocalContainer.current
    val me by container.me.collectAsState()
    if (!billingEnabled()) return
    val status: BillingStatus = me?.billing ?: return
    if (status.state == "active" || status.state == "unknown") return
    val scope = rememberCoroutineScope()
    val text = when (status.state) {
        "none" -> stringResource(R.string.billing_banner_none)
        "trial" -> stringResource(R.string.billing_banner_trial, Times.date(status.until))
        "expired" -> stringResource(R.string.billing_banner_expired, Times.date(status.until))
        else -> return
    }
    Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(12.dp), modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (status.state == "none") {
                    Button(onClick = {
                        scope.launch {
                            apiCall { container.api.startTrial() }
                                .onSuccess { container.messages.text(it.notice); container.refreshMe() }
                                .onFailure { container.messages.error(it) }
                        }
                    }) { Text(stringResource(R.string.billing_start_trial)) }
                }
                TextButton(onClick = onOpenBilling) { Text(stringResource(R.string.billing_banner_plans)) }
            }
        }
    }
}

/** The one dialog for 402 paywall / 429 daily_cap / 503 billing_unavailable, everywhere. */
@Composable
fun BillingDenialDialog(error: ApiError, onGoToBilling: () -> Unit, onDismiss: () -> Unit) {
    val showBilling = billingEnabled() && error !is ApiError.BillingUnavailable
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.billing_title)) },
        text = { Text(error.serverMessage ?: stringResource(Messages.denialText(error))) },
        confirmButton = {
            if (showBilling) {
                TextButton(onClick = { onDismiss(); onGoToBilling() }) { Text(stringResource(R.string.billing_see_plans)) }
            } else {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_close)) }
            }
        },
        dismissButton = if (showBilling) ({ TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_close)) } }) else null,
    )
}
