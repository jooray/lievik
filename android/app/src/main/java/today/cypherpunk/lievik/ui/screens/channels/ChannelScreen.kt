@file:OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)

package today.cypherpunk.lievik.ui.screens.channels

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.EventIdsBody
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.db.ChannelEventEntity
import today.cypherpunk.lievik.data.db.CurationQuery
import today.cypherpunk.lievik.data.db.CurationRow
import today.cypherpunk.lievik.data.db.CurationSort
import today.cypherpunk.lievik.data.db.EventEntity
import today.cypherpunk.lievik.data.db.UsageCounts
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.EventCard
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.util.Times

data class CurationFilters(
    val showUsed: Boolean = false,
    val search: String = "",
    val sort: CurationSort = CurationSort.Relevance,
    val limit: Int = 200,
)

/**
 * The curation queue, read from the local database (same filters as the web),
 * topped up from the server for the current filters so events older than the
 * sync window still show. Mark used/unused is optimistic and rolls back if the
 * server refuses.
 */
class ChannelViewModel(private val container: AppContainer, val channelId: Long, val selectedEventId: Long? = null) : ViewModel() {
    private val dao = container.dao
    val channel = dao.channel(channelId).map { it?.toModel() }.stateIn(viewModelScope, SharingStarted.Eagerly, null)
    val filters = MutableStateFlow(CurationFilters())
    val selection = MutableStateFlow(setOfNotNull(selectedEventId))
    val loadingRemote = MutableStateFlow(false)

    private val queue = combine(channel.filterNotNull().map { it.settings.relevanceThreshold }.distinctUntilChanged(), filters) { threshold, f ->
        CurationQuery(channelId, threshold, f.showUsed, f.search, f.sort, f.limit)
    }.flatMapLatest { dao.curation(it.toSqlite()) }

    /**
     * The queue, with the event we came from (event detail → channel) on top
     * whatever its score, threshold or used state, as on the web.
     */
    val rows = (if (selectedEventId == null) queue else combine(queue, dao.curationRow(channelId, selectedEventId)) { list, pinned ->
        if (pinned == null) list else listOf(pinned) + list.filterNot { it.event.id == selectedEventId }
    }).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val counts = channel.filterNotNull().map { it.settings.relevanceThreshold }.distinctUntilChanged()
        .flatMapLatest { dao.usageCounts(channelId, it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), UsageCounts(0, 0))

    init {
        viewModelScope.launch {
            filters.debounce(400).collect { fetchRemote(it) }
        }
    }

    private suspend fun fetchRemote(f: CurationFilters) {
        loadingRemote.value = true
        apiCall {
            container.api.channelEvents(channelId, f.showUsed.takeIf { it }, f.search.ifBlank { null }, f.sort.wire, 1, 100)
        }.onSuccess { r ->
            dao.upsertEvents(r.items.map { EventEntity.from(it.event) })
            dao.upsertChannelEvents(r.items.map { ChannelEventEntity.from(it.channelEvent) })
        }
        loadingRemote.value = false
    }

    fun refresh() = viewModelScope.launch {
        container.sync.sync()
        fetchRemote(filters.value)
    }

    fun setFilters(change: (CurationFilters) -> CurationFilters) {
        filters.value = change(filters.value)
    }

    fun toggle(eventId: Long) {
        selection.value = selection.value.let { if (eventId in it) it - eventId else it + eventId }
    }

    fun selectAll(ids: List<Long>) {
        selection.value = if (selection.value.containsAll(ids)) emptySet() else ids.toSet()
    }

    fun clearSelection() {
        selection.value = emptySet()
    }

    fun setUsed(used: Boolean) {
        val ids = selection.value.toList()
        if (ids.isEmpty()) {
            container.messages.res(R.string.channel_events_no_selection)
            return
        }
        viewModelScope.launch {
            val before = dao.channelEventsFor(channelId, ids)
            dao.setUsed(channelId, ids, used, if (used) Times.nowIso() else null)
            clearSelection()
            apiCall {
                if (used) container.api.markUsed(channelId, EventIdsBody(ids)) else container.api.markUnused(channelId, EventIdsBody(ids))
            }.onSuccess {
                container.messages.text(it.notice)
                container.sync.sync()
            }.onFailure {
                dao.upsertChannelEvents(before) // roll back
                container.messages.error(it)
            }
        }
    }

    fun rateSelected() {
        val ids = selection.value.toList()
        if (ids.isEmpty()) return
        viewModelScope.launch {
            apiCall { container.api.rateChannelEvents(channelId, EventIdsBody(ids)) }
                .onSuccess { container.messages.text(it.notice); clearSelection() }
                .onFailure { container.messages.error(it) }
        }
    }

    fun rateNew() = viewModelScope.launch {
        apiCall { container.api.rateChannel(channelId) }
            .onSuccess { container.messages.text(it.notice) }
            .onFailure { container.messages.error(it) }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ChannelScreen(id: Long, nav: NavController, selectedEventId: Long? = null) {
    val vm = appViewModel(key = "channel-$id-${selectedEventId ?: 0}") { ChannelViewModel(it, id, selectedEventId) }
    val channel by vm.channel.collectAsState()
    val filters by vm.filters.collectAsState()
    val rows by vm.rows.collectAsState()
    val counts by vm.counts.collectAsState()
    val selection by vm.selection.collectAsState()
    val loadingRemote by vm.loadingRemote.collectAsState()
    var menu by remember { mutableStateOf(false) }
    var searchText by rememberSaveable { mutableStateOf("") }
    val selecting = selection.isNotEmpty()

    ScreenScaffold(
        title = channel?.name.orEmpty(),
        onBack = { nav.popBackStack() },
        actions = {
            IconButton(onClick = { nav.navigate(Routes.contents(id)) }) {
                Icon(Icons.Filled.Description, contentDescription = stringResource(R.string.channel_content_library))
            }
            IconButton(onClick = { nav.navigate(Routes.channelEdit(id)) }) {
                Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.channel_settings))
            }
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.more_options)) }
            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.channel_rate_new)) }, onClick = { menu = false; vm.rateNew() })
                DropdownMenuItem(text = { Text(stringResource(R.string.channel_edit_criteria)) }, onClick = { menu = false; nav.navigate(Routes.channelEdit(id)) })
            }
        },
        bottomBar = {
            if (selecting) {
                BottomAppBar(windowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0)) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { vm.clearSelection() }) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.clear_selection)) }
                        Text(pluralStringResource(R.plurals.channel_selected_count, selection.size, selection.size), modifier = Modifier.weight(1f))
                        TextButton(onClick = { nav.navigate(Routes.contentNew(id, selection)); vm.clearSelection() }) {
                            Text(pluralStringResource(R.plurals.bulk_use_n, selection.size, selection.size))
                        }
                    }
                }
            }
        },
    ) { modifier ->
        PullToRefreshBox(false, onRefresh = { vm.refresh() }, modifier = modifier) {
            LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        channel?.let { c ->
                            val sub = listOfNotNull(c.language?.uppercase(), c.description?.takeIf { it.isNotBlank() }).joinToString(" · ")
                            if (sub.isNotEmpty()) Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(stringResource(R.string.channel_relevant_content), style = MaterialTheme.typography.titleMedium)
                        val unused = counts.unused ?: 0
                        val used = counts.used ?: 0
                        Text(
                            pluralStringResource(R.plurals.channel_unused_count, unused, unused) +
                                if (used > 0) " · " + pluralStringResource(R.plurals.channel_used_count, used, used) else "",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        channel?.let { c ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(stringResource(R.string.channel_threshold, c.settings.relevanceThreshold.toString()), style = MaterialTheme.typography.bodySmall)
                                LinearProgressIndicator(
                                    progress = { c.settings.relevanceThreshold / 100f },
                                    modifier = Modifier.padding(start = 8.dp).height(6.dp).weight(1f),
                                )
                            }
                        }
                        OutlinedTextField(
                            searchText, { searchText = it },
                            placeholder = { Text(stringResource(R.string.channel_search_placeholder)) },
                            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                            trailingIcon = {
                                if (filters.search.isNotEmpty() || searchText.isNotEmpty()) {
                                    IconButton(onClick = { searchText = ""; vm.setFilters { it.copy(search = "") } }) {
                                        Icon(Icons.Filled.Clear, contentDescription = stringResource(R.string.channel_clear))
                                    }
                                }
                            },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = { vm.setFilters { it.copy(search = searchText.trim()) } }),
                            modifier = Modifier.fillMaxWidth(),
                        )
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            val options = listOf(
                                CurationSort.Relevance to R.string.channel_sort_relevance,
                                CurationSort.Newest to R.string.channel_sort_newest,
                                CurationSort.Oldest to R.string.channel_sort_oldest,
                            )
                            options.forEachIndexed { index, (sort, label) ->
                                SegmentedButton(
                                    selected = filters.sort == sort,
                                    onClick = { vm.setFilters { it.copy(sort = sort) } },
                                    shape = SegmentedButtonDefaults.itemShape(index, options.size),
                                ) { Text(stringResource(label)) }
                            }
                        }
                        FlowRow(verticalArrangement = Arrangement.Center, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.heightIn(min = 48.dp)) {
                                Switch(checked = filters.showUsed, onCheckedChange = { v -> vm.setFilters { it.copy(showUsed = v) } })
                                Text(stringResource(R.string.channel_show_used), modifier = Modifier.padding(start = 8.dp))
                            }
                            val ids = rows.orEmpty().map { it.event.id }
                            if (ids.isNotEmpty()) {
                                FilterChip(
                                    selected = selecting && selection.containsAll(ids),
                                    onClick = { vm.selectAll(ids) },
                                    label = { Text(stringResource(R.string.channel_select_all_page)) },
                                    modifier = Modifier.heightIn(min = 48.dp),
                                )
                            }
                        }
                        if (selecting) {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                TextButton(onClick = { vm.setUsed(true) }) { Text(stringResource(R.string.channel_mark_used)) }
                                TextButton(onClick = { vm.setUsed(false) }) { Text(stringResource(R.string.mark_unused)) }
                                TextButton(onClick = { vm.rateSelected() }) { Text(pluralStringResource(R.plurals.bulk_rerate_n, selection.size, selection.size)) }
                            }
                        }
                        if (loadingRemote) LinearProgressIndicator(Modifier.fillMaxWidth())
                    }
                }
                val list: List<CurationRow> = rows.orEmpty()
                if (rows != null && list.isEmpty()) item { EmptyState(stringResource(R.string.channel_empty)) }
                items(list, key = { it.channelEvent.id }) { row ->
                    val event = remember(row.event) { row.event.toModel() }
                    EventCard(
                        event,
                        score = row.channelEvent.relevanceScore,
                        reason = row.channelEvent.relevanceReason,
                        used = row.channelEvent.used,
                        selecting = selecting,
                        selected = event.id in selection,
                        onToggle = { vm.toggle(event.id) },
                        onOpen = { nav.navigate(Routes.event(event.id)) },
                    )
                }
                if (list.size >= filters.limit) {
                    item {
                        TextButton(onClick = { vm.setFilters { it.copy(limit = it.limit + 200) } }, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.dev_logs_load_more))
                        }
                    }
                }
            }
        }
    }
}
