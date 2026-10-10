package today.cypherpunk.lievik.ui.screens.dashboard

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ActivityLog
import today.cypherpunk.lievik.data.api.Stats
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.ui.components.BillingBanner
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.EventCard
import today.cypherpunk.lievik.ui.components.LocalContainer
import today.cypherpunk.lievik.ui.components.ProgressRow
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.util.Times

/**
 * Active jobs, polled while the screen is visible and anything runs. When the
 * last one finishes, a sync pulls in what it produced.
 */
class JobsPoller(private val container: AppContainer) {
    val jobs = MutableStateFlow<List<ActivityLog>>(emptyList())
    private var job: Job? = null

    fun start(scope: kotlinx.coroutines.CoroutineScope) {
        if (job?.isActive == true) return
        job = scope.launch {
            while (true) {
                val result = apiCall { container.api.activeJobs() }.getOrNull()
                if (result != null) {
                    val wasRunning = jobs.value.isNotEmpty()
                    jobs.value = result.jobs
                    if (wasRunning && result.jobs.isEmpty()) container.sync.sync()
                }
                delay(if (jobs.value.isEmpty()) 15_000 else 3_000)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    fun cancel(scope: kotlinx.coroutines.CoroutineScope, id: Long) = scope.launch {
        apiCall { container.api.cancelJob(id) }
            .onSuccess { container.messages.text(it.notice); jobs.value = jobs.value.filterNot { j -> j.id == id } }
            .onFailure { container.messages.error(it) }
    }
}

class DashboardViewModel(private val container: AppContainer) : ViewModel() {
    val remoteStats = MutableStateFlow<Stats?>(null)
    val refreshing = MutableStateFlow(false)
    val poller = JobsPoller(container)
    val recent = container.dao.recentEvents(20).map { rows -> rows.map { it.toModel() } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val sourceCount = container.dao.sources().map { rows -> rows.count { it.sourceType != "manual" } }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)
    val channelCount = container.dao.channels().map { it.size }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)
    val eventCount = container.dao.eventCount().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)

    init { refresh() }

    fun refresh() = viewModelScope.launch {
        refreshing.value = true
        apiCall { container.api.dashboard() }.onSuccess {
            remoteStats.value = it.stats
            poller.jobs.value = it.activeJobs
        }
        container.sync.sync()
        refreshing.value = false
    }

    fun rateAll() = viewModelScope.launch {
        apiCall { container.api.rateAll() }
            .onSuccess { container.messages.text(it.notice); poller.jobs.value = poller.jobs.value; poller.stop(); poller.start(viewModelScope) }
            .onFailure { container.messages.error(it) }
    }

    fun refreshAllSources() = viewModelScope.launch {
        apiCall { container.api.refreshAllSources() }
            .onSuccess { container.messages.text(it.notice); poller.stop(); poller.start(viewModelScope) }
            .onFailure { container.messages.error(it) }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DashboardScreen(nav: NavController) {
    val vm = appViewModel { DashboardViewModel(it) }
    val container = LocalContainer.current
    val me by container.me.collectAsState()
    val remote by vm.remoteStats.collectAsState()
    val refreshing by vm.refreshing.collectAsState()
    val jobs by vm.poller.jobs.collectAsState()
    val recent by vm.recent.collectAsState()
    val sources by vm.sourceCount.collectAsState()
    val channels by vm.channelCount.collectAsState()
    val events by vm.eventCount.collectAsState()

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.poller.start(vm.viewModelScope) }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { vm.poller.stop() }

    val stats = remote ?: me?.stats ?: Stats(sources, channels, events, 0)
    val sourceTotal = maxOf(stats.sources, sources)
    val channelTotal = maxOf(stats.channels, channels)

    ScreenScaffold(
        title = stringResource(R.string.dashboard_title),
        actions = {
            IconButton(onClick = { vm.refresh() }) { Icon(Icons.Filled.Sync, contentDescription = stringResource(R.string.sync_now)) }
        },
    ) { modifier ->
        PullToRefreshBox(isRefreshing = refreshing, onRefresh = { vm.refresh() }, modifier = modifier) {
            LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    me?.user?.let {
                        Text(stringResource(R.string.dashboard_welcome_back, it.label), style = MaterialTheme.typography.titleMedium)
                    }
                }
                item { BillingBanner(onOpenBilling = { nav.navigate(Routes.BILLING) }) }
                item {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp), maxItemsInEachRow = 2) {
                        StatCard(stringResource(R.string.dashboard_sources), Times.number(sourceTotal), Modifier.weight(1f)) { nav.navigate(Routes.SOURCES) }
                        StatCard(stringResource(R.string.dashboard_channels), Times.number(channelTotal), Modifier.weight(1f)) { nav.navigate(Routes.CHANNELS) }
                        StatCard(stringResource(R.string.dashboard_events), Times.number(maxOf(stats.events, events)), Modifier.weight(1f)) { nav.navigate(Routes.EVENTS) }
                        StatCard(
                            stringResource(R.string.dashboard_ask_content),
                            stringResource(R.string.dashboard_indexed, Times.number(stats.embedded), Times.number(stats.events)),
                            Modifier.weight(1f),
                        ) { nav.navigate(Routes.ASK) }
                    }
                }
                if (jobs.isNotEmpty()) {
                    item {
                        SectionCard(stringResource(R.string.dashboard_jobs_running)) {
                            jobs.forEach { job ->
                                ProgressRow(job.message, job.percent) {
                                    IconButton(onClick = { vm.poller.cancel(vm.viewModelScope, job.id) }) {
                                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.activity_cancel_job))
                                    }
                                }
                            }
                        }
                    }
                }
                if (sourceTotal == 0) {
                    item {
                        SectionCard(stringResource(R.string.dashboard_step1_title)) {
                            Text(stringResource(R.string.dashboard_step1_body), style = MaterialTheme.typography.bodyMedium)
                            Button(onClick = { nav.navigate(Routes.SOURCE_NEW) }) { Text(stringResource(R.string.dashboard_add_source)) }
                        }
                    }
                }
                if (channelTotal == 0) {
                    item {
                        SectionCard(stringResource(R.string.dashboard_step2_title)) {
                            Text(stringResource(R.string.dashboard_step2_body), style = MaterialTheme.typography.bodyMedium)
                            Button(onClick = { nav.navigate(Routes.CHANNEL_NEW) }) { Text(stringResource(R.string.dashboard_create_channel)) }
                            TextButton(onClick = { nav.navigate(Routes.CHANNELS_AI) }) { Text(stringResource(R.string.dashboard_describe_to_ai)) }
                        }
                    }
                }
                item {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (channelTotal > 0) Button(onClick = { vm.rateAll() }) { Text(stringResource(R.string.dashboard_rate_all_unrated)) }
                        OutlinedButton(onClick = { nav.navigate(Routes.MANUAL_EVENT) }) { Text(stringResource(R.string.dashboard_add_manually)) }
                        if (sourceTotal > 0) OutlinedButton(onClick = { vm.refreshAllSources() }) { Text(stringResource(R.string.dashboard_refresh_all_sources)) }
                    }
                }
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.dashboard_recent_events), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        if (recent.isNotEmpty()) TextButton(onClick = { nav.navigate(Routes.EVENTS) }) { Text(stringResource(R.string.dashboard_view_all_events)) }
                    }
                }
                if (recent.isEmpty()) {
                    item {
                        EmptyState(stringResource(R.string.dashboard_no_events_title), stringResource(R.string.dashboard_no_events_body)) {
                            TextButton(onClick = { nav.navigate(Routes.SOURCES) }) { Text(stringResource(R.string.dashboard_manage_sources)) }
                        }
                    }
                }
                items(recent, key = { it.id }) { event ->
                    EventCard(event, showTopChannels = true, onOpen = { nav.navigate(Routes.event(event.id)) })
                }
            }
        }
    }
}

@Composable
private fun StatCard(label: String, value: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Card(
        modifier = modifier.widthIn(min = 140.dp).heightIn(min = 88.dp).clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(1.dp),
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary)
        }
    }
}
