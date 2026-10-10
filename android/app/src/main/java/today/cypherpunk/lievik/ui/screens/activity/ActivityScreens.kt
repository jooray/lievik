package today.cypherpunk.lievik.ui.screens.activity

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ActivityLog
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.DevLog
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.ErrorState
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.ProgressRow
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.ui.screens.dashboard.JobsPoller
import today.cypherpunk.lievik.util.Times

class ActivityViewModel(private val container: AppContainer) : ViewModel() {
    val logs = MutableStateFlow<List<ActivityLog>>(emptyList())
    val staleCount = MutableStateFlow(0)
    val error = MutableStateFlow<ApiError?>(null)
    val loading = MutableStateFlow(true)
    val hasMore = MutableStateFlow(false)
    val poller = JobsPoller(container)
    private var page = 1

    init { refresh() }

    fun refresh() = viewModelScope.launch {
        loading.value = true
        page = 1
        apiCall { container.api.activityLogs(1) }
            .onSuccess { r ->
                logs.value = r.activityLogs
                poller.jobs.value = r.active
                staleCount.value = r.staleCount
                hasMore.value = r.meta.page < r.meta.totalPages
                error.value = null
            }
            .onFailure { error.value = it as ApiError }
        loading.value = false
    }

    fun more() = viewModelScope.launch {
        apiCall { container.api.activityLogs(page + 1) }.onSuccess { r ->
            page += 1
            logs.value = logs.value + r.activityLogs
            hasMore.value = r.meta.page < r.meta.totalPages
        }.onFailure { container.messages.error(it) }
    }

    fun retry(id: Long) = viewModelScope.launch {
        apiCall { container.api.retryJob(id) }
            .onSuccess { container.messages.text(it.notice); refresh() }
            .onFailure { container.messages.error(it) }
    }

    fun cleanup() = viewModelScope.launch {
        apiCall { container.api.cleanupStale() }
            .onSuccess { container.messages.text(it.notice); refresh() }
            .onFailure { container.messages.error(it) }
    }
}

@Composable
fun statusLabel(status: String?): String = when (status) {
    "pending" -> stringResource(R.string.activity_status_pending)
    "running" -> stringResource(R.string.activity_status_running)
    "completed" -> stringResource(R.string.activity_status_completed)
    "failed" -> stringResource(R.string.activity_status_failed)
    else -> status.orEmpty()
}

@Composable
fun typeLabel(type: String?): String = when (type) {
    "ingestion" -> stringResource(R.string.activity_type_ingestion)
    "rating" -> stringResource(R.string.activity_type_rating)
    else -> type.orEmpty()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityScreen(nav: NavController) {
    val vm = appViewModel { ActivityViewModel(it) }
    val logs by vm.logs.collectAsState()
    val active by vm.poller.jobs.collectAsState()
    val stale by vm.staleCount.collectAsState()
    val error by vm.error.collectAsState()
    val loading by vm.loading.collectAsState()
    val hasMore by vm.hasMore.collectAsState()
    var confirmCleanup by remember { mutableStateOf(false) }
    var confirmCancel by remember { mutableStateOf<Long?>(null) }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.poller.start(vm.viewModelScope) }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { vm.poller.stop() }

    if (confirmCleanup) {
        ConfirmDialog(pluralStringResource(R.plurals.activity_confirm_cleanup, stale, stale), pluralStringResource(R.plurals.activity_cleanup, stale, stale), { vm.cleanup() }, { confirmCleanup = false })
    }
    confirmCancel?.let { id ->
        ConfirmDialog(stringResource(R.string.activity_confirm_cancel), stringResource(R.string.activity_cancel_job), { vm.poller.cancel(vm.viewModelScope, id) }, { confirmCancel = null }, destructive = true)
    }

    ScreenScaffold(title = stringResource(R.string.activity_title), onBack = { nav.popBackStack() }) { modifier ->
        PullToRefreshBox(loading && logs.isNotEmpty(), onRefresh = { vm.refresh() }, modifier = modifier) {
            when {
                loading && logs.isEmpty() && error == null -> LoadingBox()
                error != null && logs.isEmpty() -> ErrorState(error!!, onRetry = { vm.refresh() })
                else -> LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    item { Text(stringResource(R.string.activity_subtitle), style = MaterialTheme.typography.bodySmall) }
                    if (active.isNotEmpty()) item {
                        SectionCard(stringResource(R.string.activity_active_jobs)) {
                            active.forEach { job ->
                                ProgressRow(job.message, job.percent) {
                                    IconButton(onClick = { confirmCancel = job.id }) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.activity_cancel_job)) }
                                }
                            }
                        }
                    }
                    if (stale > 0) item {
                        OutlinedButton(onClick = { confirmCleanup = true }) { Text(pluralStringResource(R.plurals.activity_cleanup, stale, stale)) }
                    }
                    item { Text(stringResource(R.string.activity_history), style = MaterialTheme.typography.titleMedium) }
                    if (logs.isEmpty()) item { EmptyState(stringResource(R.string.activity_empty_title), stringResource(R.string.activity_empty_hint)) }
                    items(logs, key = { it.id }) { log ->
                        LogRow(log, onRetry = { vm.retry(log.id) }, onDevLogs = { nav.navigate(Routes.devLogs(log.id)) })
                    }
                    if (hasMore) item { TextButton(onClick = { vm.more() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.dev_logs_load_more)) } }
                }
            }
        }
    }
}

@Composable
private fun LogRow(log: ActivityLog, onRetry: () -> Unit, onDevLogs: () -> Unit) {
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), elevation = CardDefaults.cardElevation(1.dp)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Tag(typeLabel(log.activityType))
                Tag(statusLabel(log.status))
                if (log.stale) Tag(stringResource(R.string.activity_stale))
                Text(Times.relative(log.createdAt), style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
            }
            log.message?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (log.status == "failed" || log.stale) {
                    TextButton(onClick = onRetry) {
                        Text(stringResource(if (log.activityType == "rating") R.string.activity_retry_rating else R.string.activity_retry_ingestion))
                    }
                }
                if (log.devLogCount > 0) {
                    TextButton(onClick = onDevLogs) { Text(pluralStringResource(R.plurals.activity_dev_logs, log.devLogCount, log.devLogCount)) }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- developer logs

class DevLogsViewModel(private val container: AppContainer, private val id: Long) : ViewModel() {
    val logs = MutableStateFlow<List<DevLog>?>(null)
    val total = MutableStateFlow(0)
    val error = MutableStateFlow<ApiError?>(null)
    val hasMore = MutableStateFlow(false)
    private var page = 0

    init { more() }

    fun more() = viewModelScope.launch {
        apiCall { container.api.devLogs(id, page + 1) }
            .onSuccess { r ->
                page += 1
                logs.value = logs.value.orEmpty() + r.devLogs
                total.value = r.meta.totalCount
                hasMore.value = r.meta.page < r.meta.totalPages
                error.value = null
            }
            .onFailure { error.value = it as ApiError }
    }
}

@Composable
fun DevLogsScreen(id: Long, onBack: () -> Unit) {
    val vm = appViewModel(key = "devlogs-$id") { DevLogsViewModel(it, id) }
    val logs by vm.logs.collectAsState()
    val total by vm.total.collectAsState()
    val error by vm.error.collectAsState()
    val hasMore by vm.hasMore.collectAsState()
    ScreenScaffold(title = stringResource(R.string.dev_logs_title), onBack = onBack) { modifier ->
        val list = logs
        when {
            list == null && error != null -> ErrorState(error!!, onRetry = { vm.more() }, modifier = modifier)
            list == null -> LoadingBox(modifier)
            list.isEmpty() -> EmptyState(stringResource(R.string.dev_logs_empty_title), stringResource(R.string.dev_logs_empty_hint), modifier = modifier)
            else -> LazyColumn(modifier, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item {
                    Text(stringResource(R.string.dev_logs_heading, total.toString()), style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(R.string.dev_logs_subtitle), style = MaterialTheme.typography.bodySmall)
                }
                items(list, key = { it.id }) { DevLogRow(it) }
                if (hasMore) item { TextButton(onClick = { vm.more() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.dev_logs_load_more)) } }
            }
        }
    }
}

@Composable
private fun DevLogRow(log: DevLog) {
    var open by rememberSaveable(log.id) { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                log.logType?.let { Tag(it) }
                Text(Times.dateTime(log.createdAt), style = MaterialTheme.typography.bodySmall)
            }
            log.message?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
            log.detail("score")?.let { Text(stringResource(R.string.dev_logs_score) + " " + it, style = MaterialTheme.typography.bodySmall) }
            log.detail("reason")?.let { Text(stringResource(R.string.dev_logs_reason) + " " + it, style = MaterialTheme.typography.bodySmall) }
            if (log.details != null) {
                TextButton(onClick = { open = !open }) { Text(stringResource(R.string.dev_logs_view_details)) }
                if (open) {
                    DetailBlock(R.string.dev_logs_system_prompt, log.detail("system_prompt"))
                    DetailBlock(R.string.dev_logs_user_prompt, log.detail("user_prompt"))
                    DetailBlock(R.string.dev_logs_content_evaluated, log.detail("content"))
                    DetailBlock(R.string.dev_logs_raw_response, log.detail("raw_response"))
                    DetailBlock(R.string.dev_logs_json_details, pretty(log.details))
                }
            }
        }
    }
}

@Composable
private fun DetailBlock(label: Int, text: String?) {
    if (text.isNullOrBlank()) return
    Text(stringResource(label), style = MaterialTheme.typography.labelLarge)
    Text(
        text, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).clickable {},
    )
}

private val prettyJson = kotlinx.serialization.json.Json { prettyPrint = true }

private fun pretty(element: JsonElement?): String? = element?.let { prettyJson.encodeToString(JsonElement.serializer(), it) }
