package today.cypherpunk.lievik.ui.screens.billing

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.BillingResponse
import today.cypherpunk.lievik.data.api.BillingStatus
import today.cypherpunk.lievik.data.api.ChargeBody
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.ui.components.ErrorState
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.screens.settings.RadioRow
import today.cypherpunk.lievik.util.Links
import today.cypherpunk.lievik.util.Times

/**
 * Paid access, as the web's /billing. Paying opens BTCPay's checkout in a
 * Custom Tab (Google Play's payment rules are why this is a browser hand-off;
 * the app ships through Zapstore/Obtainium/direct APK). Back in the app, the
 * invoice is polled until it settles.
 */
class BillingViewModel(private val container: AppContainer) : ViewModel() {
    val data = MutableStateFlow<BillingResponse?>(null)
    val error = MutableStateFlow<ApiError?>(null)
    val busy = MutableStateFlow(false)
    /** The invoice opened from this screen, awaiting payment. */
    val awaiting = MutableStateFlow<String?>(null)
    private var poll: Job? = null

    init { load() }

    fun load() = viewModelScope.launch {
        apiCall { container.api.billing() }
            .onSuccess { r ->
                data.value = r
                error.value = null
                r.notice?.let { container.messages.text(it); container.refreshMe() }
            }
            .onFailure { error.value = it as ApiError }
    }

    fun startTrial() = viewModelScope.launch {
        busy.value = true
        apiCall { container.api.startTrial() }
            .onSuccess { r -> container.messages.text(r.notice); container.refreshMe(); load() }
            .onFailure { container.messages.error(it) }
        busy.value = false
    }

    fun pay(plan: String, sats: Long?, open: (String) -> Unit) = viewModelScope.launch {
        busy.value = true
        apiCall { container.api.createCharge(ChargeBody(plan, sats)) }
            .onSuccess { charge ->
                awaiting.value = charge.invoiceId
                open(charge.checkoutUrl)
            }
            .onFailure { container.messages.error(it) }
        busy.value = false
    }

    fun watch(invoiceId: String) {
        awaiting.value = invoiceId
        resumePolling()
    }

    /** Called on resume: poll the awaited invoice every 3 s for up to 3 minutes. */
    fun resumePolling() {
        val invoice = awaiting.value ?: return
        poll?.cancel()
        poll = viewModelScope.launch {
            repeat(60) {
                val status = apiCall { container.api.charge(invoice) }.getOrNull()
                if (status?.settled == true) {
                    awaiting.value = null
                    status.notice?.let { container.messages.text(it) }
                    container.refreshMe()
                    load()
                    return@launch
                }
                delay(3000)
            }
        }
    }

    fun checkNow() {
        val invoice = awaiting.value ?: return
        viewModelScope.launch {
            val status = apiCall { container.api.charge(invoice) }.onFailure { container.messages.error(it) }.getOrNull() ?: return@launch
            if (status.settled) {
                awaiting.value = null
                status.notice?.let { container.messages.text(it) }
                container.refreshMe()
                load()
            } else {
                container.messages.res(R.string.billing_not_settled)
            }
        }
    }

    fun pausePolling() {
        poll?.cancel()
    }
}

@Composable
private fun planName(plan: String) = when (plan) {
    "all-access" -> stringResource(R.string.billing_plan_all_access_name)
    "lievik" -> stringResource(R.string.billing_plan_lievik_name)
    else -> plan
}

@Composable
private fun planCovers(plan: String): String? = when (plan) {
    "all-access" -> stringResource(R.string.billing_plan_all_access_covers)
    "lievik" -> stringResource(R.string.billing_plan_lievik_covers)
    else -> null
}

@Composable
private fun productName(product: String) = when (product) {
    "nalgorithm" -> stringResource(R.string.billing_product_nalgorithm)
    "emanator-ai", "emanator_ai" -> stringResource(R.string.billing_product_emanator_ai)
    "lievik" -> stringResource(R.string.billing_product_lievik)
    else -> product
}

@Composable
fun BillingScreen(onBack: () -> Unit) {
    val vm = appViewModel { BillingViewModel(it) }
    BillingContent(vm, onBack)
}

@Composable
private fun BillingContent(vm: BillingViewModel, onBack: () -> Unit) {
    val data by vm.data.collectAsState()
    val error by vm.error.collectAsState()
    val busy by vm.busy.collectAsState()
    val awaiting by vm.awaiting.collectAsState()
    val context = LocalContext.current

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.resumePolling(); vm.load() }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { vm.pausePolling() }

    ScreenScaffold(title = stringResource(R.string.billing_title), onBack = onBack) { modifier ->
        val d = data
        if (d == null) {
            if (error != null) ErrorState(error!!, onRetry = { vm.load() }, modifier = modifier) else LoadingBox(modifier)
            return@ScreenScaffold
        }
        Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Hint(stringResource(R.string.billing_intro))
            StatusCard(d.status, busy, onStartTrial = { vm.startTrial() })

            awaiting?.let {
                SectionCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text(stringResource(R.string.billing_waiting_payment), modifier = Modifier.padding(start = 12.dp).weight(1f))
                    }
                    Hint(stringResource(R.string.billing_payment_hint))
                    OutlinedButton(onClick = { vm.checkNow() }) { Text(stringResource(R.string.billing_check_payment)) }
                }
            }

            if (d.pendingCharges.isNotEmpty()) {
                SectionCard(stringResource(R.string.billing_pending_title)) {
                    d.pendingCharges.forEach { charge ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(charge.plan?.let { planName(it) } ?: charge.invoiceId, modifier = Modifier.weight(1f))
                            charge.checkoutUrl?.let { url ->
                                TextButton(onClick = { vm.watch(charge.invoiceId); Links.openUrl(context, url) }) { Text(stringResource(R.string.billing_open_invoice)) }
                            }
                        }
                    }
                }
            }

            if (d.plans.isEmpty()) {
                Text(stringResource(R.string.billing_plans_unavailable), color = MaterialTheme.colorScheme.error)
            } else {
                d.plans.forEach { plan ->
                    SectionCard(planName(plan.plan)) {
                        Text(
                            stringResource(R.string.billing_plan_price, Times.number(plan.sats), plan.days.toString()),
                            style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
                        )
                        planCovers(plan.plan)?.let { Hint(it) }
                        Button(onClick = { vm.pay(plan.plan, null) { url -> Links.openUrl(context, url) } }, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.billing_plan_pay, Times.number(plan.sats)))
                        }
                    }
                }
                CustomAmount(d, busy) { plan, sats -> vm.pay(plan, sats) { url -> Links.openUrl(context, url) } }
            }
            Hint(stringResource(R.string.billing_self_host))
        }
    }
}

@Composable
private fun StatusCard(status: BillingStatus, busy: Boolean, onStartTrial: () -> Unit) {
    SectionCard(stringResource(R.string.billing_status_title)) {
        Text(
            when (status.state) {
                "active" -> stringResource(R.string.billing_status_active, Times.date(status.until))
                "trial" -> stringResource(R.string.billing_status_trial, Times.date(status.until))
                "expired" -> stringResource(R.string.billing_status_expired, Times.date(status.until))
                "none" -> stringResource(R.string.billing_status_none)
                else -> stringResource(R.string.billing_status_unknown)
            },
        )
        if (status.state == "none") {
            Button(onClick = onStartTrial, enabled = !busy) { Text(stringResource(R.string.billing_start_trial)) }
        }
        status.otherProducts.filter { it.state == "active" || it.state == "trial" }.forEach { other ->
            Hint(stringResource(R.string.billing_status_other, productName(other.product), Times.date(other.until)))
        }
        status.npub?.let { Hint(stringResource(R.string.billing_status_npub, it)) }
    }
}

@Composable
private fun CustomAmount(data: BillingResponse, busy: Boolean, onPay: (String, Long) -> Unit) {
    var plan by rememberSaveable { mutableStateOf(data.plans.first().plan) }
    var sats by rememberSaveable { mutableStateOf("") }
    val lievik = data.plans.firstOrNull { it.plan == "lievik" } ?: data.plans.first()
    val minDays = if (lievik.sats > 0) (data.minSats * lievik.days / lievik.sats.toDouble()) else 0.0
    val daysText = if (minDays % 1.0 == 0.0) minDays.toLong().toString() else String.format(today.cypherpunk.lievik.util.AppLocale.locale(), "%.1f", minDays)
    val amount = sats.toLongOrNull()
    val valid = amount != null && amount in data.minSats..data.maxSats
    SectionCard(stringResource(R.string.billing_custom_title)) {
        Hint(stringResource(R.string.billing_custom_help, Times.number(data.minSats), daysText))
        Text(stringResource(R.string.billing_custom_plan), style = MaterialTheme.typography.labelLarge)
        data.plans.forEach { p -> RadioRow(planName(p.plan), selected = plan == p.plan, onClick = { plan = p.plan }) }
        OutlinedTextField(
            sats, { sats = it.filter(Char::isDigit).take(9) },
            label = { Text(stringResource(R.string.billing_custom_sats)) },
            singleLine = true,
            isError = sats.isNotEmpty() && !valid,
            supportingText = {
                if (sats.isNotEmpty() && !valid) Text(stringResource(R.string.billing_sats_range, Times.number(data.minSats), Times.number(data.maxSats)))
            },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = { onPay(plan, amount!!) }, enabled = valid && !busy) { Text(stringResource(R.string.billing_custom_pay)) }
    }
}
