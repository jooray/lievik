@file:OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)

package today.cypherpunk.lievik.ui.screens.events

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.ChannelEvent
import today.cypherpunk.lievik.data.api.ChannelEventIdsBody
import today.cypherpunk.lievik.data.api.Event
import today.cypherpunk.lievik.data.api.EventDetailResponse
import today.cypherpunk.lievik.data.api.ManualEventBody
import today.cypherpunk.lievik.data.api.RateEventsBody
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.db.ChannelEventEntity
import today.cypherpunk.lievik.data.db.EventEntity
import today.cypherpunk.lievik.data.db.EventsQuery
import today.cypherpunk.lievik.ui.components.Avatar
import today.cypherpunk.lievik.ui.components.BusyButton
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.ErrorState
import today.cypherpunk.lievik.ui.components.EventCard
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.NostrContentView
import today.cypherpunk.lievik.ui.components.RelevanceChip
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.components.eventTypeLabel
import today.cypherpunk.lievik.ui.components.sourceLabel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.util.Links
import today.cypherpunk.lievik.util.Times

// ---------------------------------------------------------------- list

data class EventFilters(val sourceId: Long? = null, val eventType: String? = null, val search: String = "", val limit: Int = 200)

class EventsViewModel(private val container: AppContainer) : ViewModel() {
    val filters = MutableStateFlow(EventFilters())
    val selection = MutableStateFlow<Set<Long>>(emptySet())
    val remoteTotal = MutableStateFlow<Int?>(null)
    val refreshing = MutableStateFlow(false)
    val sources = container.dao.sources().map { rows -> rows.map { it.toModel() } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val events = filters.flatMapLatest { f -> container.dao.events(EventsQuery(f.sourceId, f.eventType, f.search, f.limit).toSqlite()) }
        .map { rows -> rows.map(EventEntity::toModel) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    init {
        viewModelScope.launch { filters.debounce(400).collect { fetch(it) } }
    }

    private suspend fun fetch(f: EventFilters) {
        apiCall { container.api.events(f.sourceId, f.eventType, f.search.ifBlank { null }, 1) }
            .onSuccess { r ->
                remoteTotal.value = r.meta.totalCount
                container.dao.upsertEvents(r.events.map(EventEntity::from))
            }
            .onFailure { remoteTotal.value = null }
    }

    fun refresh() = viewModelScope.launch {
        refreshing.value = true
        container.sync.sync()
        fetch(filters.value)
        refreshing.value = false
    }

    fun setFilters(change: (EventFilters) -> EventFilters) {
        filters.value = change(filters.value).copy(limit = 200)
        selection.value = emptySet()
    }

    fun more() {
        filters.value = filters.value.copy(limit = filters.value.limit + 200)
    }

    fun toggle(id: Long) {
        selection.value = selection.value.let { if (id in it) it - id else it + id }
    }

    fun selectAll(ids: List<Long>) {
        selection.value = if (selection.value.containsAll(ids)) emptySet() else ids.toSet()
    }

    fun rateSelected() = rate(RateEventsBody(eventIds = selection.value.toList()))

    fun rateMatching() {
        val f = filters.value
        rate(RateEventsBody(sourceId = f.sourceId, eventType = f.eventType, search = f.search.ifBlank { null }))
    }

    private fun rate(body: RateEventsBody) = viewModelScope.launch {
        apiCall { container.api.rateEvents(body) }
            .onSuccess { container.messages.text(it.notice); selection.value = emptySet() }
            .onFailure { container.messages.error(it) }
    }
}

private val EVENT_TYPES = listOf("original", "reply", "repost", "long_form")

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun EventsScreen(nav: NavController) {
    val vm = appViewModel { EventsViewModel(it) }
    val filters by vm.filters.collectAsState()
    val events by vm.events.collectAsState()
    val selection by vm.selection.collectAsState()
    val sources by vm.sources.collectAsState()
    val total by vm.remoteTotal.collectAsState()
    val refreshing by vm.refreshing.collectAsState()
    var searchText by rememberSaveable { mutableStateOf("") }
    var sourceMenu by remember { mutableStateOf(false) }
    var typeMenu by remember { mutableStateOf(false) }
    var confirmRerate by remember { mutableStateOf(false) }
    val selecting = selection.isNotEmpty()
    val matching = total ?: events?.size ?: 0

    if (confirmRerate) {
        ConfirmDialog(
            pluralStringResource(R.plurals.events_rerate_confirm, matching, matching),
            stringResource(R.string.events_rerate_all, matching),
            onConfirm = { vm.rateMatching() }, onDismiss = { confirmRerate = false },
        )
    }

    ScreenScaffold(
        title = stringResource(R.string.events_title),
        floatingActionButton = {
            if (!selecting) FloatingActionButton(onClick = { nav.navigate(Routes.MANUAL_EVENT) }) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.nav_add_event))
            }
        },
        bottomBar = {
            if (selecting) BottomAppBar(windowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { vm.selectAll(emptyList()) }) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.clear_selection)) }
                    Text(pluralStringResource(R.plurals.events_selected, selection.size, selection.size), modifier = Modifier.weight(1f))
                    TextButton(onClick = { vm.rateSelected() }) { Text(pluralStringResource(R.plurals.bulk_rerate_n, selection.size, selection.size)) }
                }
            }
        },
    ) { modifier ->
        PullToRefreshBox(refreshing, onRefresh = { vm.refresh() }, modifier = modifier) {
            LazyColumn(contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Hint(pluralStringResource(R.plurals.events_subtitle, matching, matching))
                        OutlinedTextField(
                            searchText, { searchText = it },
                            placeholder = { Text(stringResource(R.string.events_search_placeholder)) },
                            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                            trailingIcon = {
                                if (searchText.isNotEmpty() || filters.search.isNotEmpty()) IconButton(onClick = { searchText = ""; vm.setFilters { it.copy(search = "") } }) {
                                    Icon(Icons.Filled.Clear, contentDescription = stringResource(R.string.events_clear))
                                }
                            },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = { vm.setFilters { it.copy(search = searchText.trim()) } }),
                            modifier = Modifier.fillMaxWidth(),
                        )
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Column {
                                val current = sources.firstOrNull { it.id == filters.sourceId }
                                FilterChip(
                                    selected = filters.sourceId != null, onClick = { sourceMenu = true },
                                    label = { Text(current?.let { sourceLabel(it.name, it.sourceType) } ?: stringResource(R.string.events_all_sources)) },
                                    modifier = Modifier.heightIn(min = 48.dp),
                                )
                                DropdownMenu(sourceMenu, onDismissRequest = { sourceMenu = false }) {
                                    DropdownMenuItem(text = { Text(stringResource(R.string.events_all_sources)) }, onClick = { sourceMenu = false; vm.setFilters { it.copy(sourceId = null) } })
                                    sources.forEach { s ->
                                        DropdownMenuItem(text = { Text(sourceLabel(s.name, s.sourceType)) }, onClick = { sourceMenu = false; vm.setFilters { it.copy(sourceId = s.id) } })
                                    }
                                }
                            }
                            Column {
                                FilterChip(
                                    selected = filters.eventType != null, onClick = { typeMenu = true },
                                    label = { Text(eventTypeLabel(filters.eventType) ?: stringResource(R.string.events_all_types)) },
                                    modifier = Modifier.heightIn(min = 48.dp),
                                )
                                DropdownMenu(typeMenu, onDismissRequest = { typeMenu = false }) {
                                    DropdownMenuItem(text = { Text(stringResource(R.string.events_all_types)) }, onClick = { typeMenu = false; vm.setFilters { it.copy(eventType = null) } })
                                    EVENT_TYPES.forEach { t ->
                                        DropdownMenuItem(text = { Text(eventTypeLabel(t).orEmpty()) }, onClick = { typeMenu = false; vm.setFilters { it.copy(eventType = t) } })
                                    }
                                }
                            }
                            val ids = events.orEmpty().map { it.id }
                            if (ids.isNotEmpty()) {
                                FilterChip(
                                    selected = selecting && selection.containsAll(ids), onClick = { vm.selectAll(ids) },
                                    label = { Text(stringResource(R.string.events_select_all_page)) }, modifier = Modifier.heightIn(min = 48.dp),
                                )
                                TextButton(onClick = { confirmRerate = true }, modifier = Modifier.heightIn(min = 48.dp)) {
                                    Text(stringResource(R.string.events_rerate_all, matching))
                                }
                            }
                        }
                    }
                }
                val list = events
                when {
                    list == null -> item { LoadingBox() }
                    list.isEmpty() -> item { EmptyState(stringResource(R.string.events_empty_title), stringResource(R.string.events_empty_body)) }
                    else -> {
                        items(list, key = { it.id }) { e ->
                            EventCard(
                                e, showTopChannels = true, selecting = selecting, selected = e.id in selection,
                                onToggle = { vm.toggle(e.id) }, onOpen = { nav.navigate(Routes.event(e.id)) },
                            )
                        }
                        if (list.size >= filters.limit) item {
                            TextButton(onClick = { vm.more() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.dev_logs_load_more)) }
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- detail

/**
 * Online: GET /events/:id (scores with reasons, linked content). Offline: the
 * cached event and its cached ratings.
 */
class EventDetailViewModel(private val container: AppContainer, private val id: Long) : ViewModel() {
    val detail = MutableStateFlow<EventDetailResponse?>(null)
    val error = MutableStateFlow<ApiError?>(null)
    val selected = MutableStateFlow<Set<Long>>(emptySet())

    init { load() }

    fun load() = viewModelScope.launch {
        apiCall { container.api.event(id) }
            .onSuccess { r ->
                detail.value = r
                error.value = null
                container.dao.upsertEvents(listOf(EventEntity.from(r.event)))
                container.dao.upsertChannelEvents(r.channelEvents.map(ChannelEventEntity::from))
            }
            .onFailure { e ->
                val cached = container.dao.event(id).first()
                if (cached != null) {
                    val channels = container.dao.channels().first().associateBy { it.id }
                    val ratings = container.dao.channelEventsForEvent(id).first().map { it.toModel().copy(channelName = channels[it.channelId]?.name) }
                    detail.value = EventDetailResponse(cached.toModel(), ratings)
                }
                error.value = e as ApiError
            }
    }

    fun toggle(channelEventId: Long) {
        selected.value = selected.value.let { if (channelEventId in it) it - channelEventId else it + channelEventId }
    }

    fun selectAll(ids: List<Long>) {
        selected.value = if (selected.value.containsAll(ids)) emptySet() else ids.toSet()
    }

    fun markUsed() {
        val ids = selected.value.toList()
        if (ids.isEmpty()) {
            container.messages.res(R.string.event_no_channels_selected)
            return
        }
        viewModelScope.launch {
            apiCall { container.api.markEventUsed(id, ChannelEventIdsBody(ids)) }
                .onSuccess { container.messages.text(it.notice); selected.value = emptySet(); load(); container.sync.sync() }
                .onFailure { container.messages.error(it) }
        }
    }

    fun rerate() = viewModelScope.launch {
        apiCall { container.api.rateEvents(RateEventsBody(eventIds = listOf(id))) }
            .onSuccess { container.messages.text(it.notice) }
            .onFailure { container.messages.error(it) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EventDetailScreen(id: Long, nav: NavController) {
    val vm = appViewModel(key = "event-$id") { EventDetailViewModel(it, id) }
    val detail by vm.detail.collectAsState()
    val error by vm.error.collectAsState()
    val selected by vm.selected.collectAsState()
    val context = LocalContext.current
    var confirmRerate by remember { mutableStateOf(false) }

    if (confirmRerate) {
        ConfirmDialog(stringResource(R.string.events_rerate_one_confirm), stringResource(R.string.event_rerate), onConfirm = { vm.rerate() }, onDismiss = { confirmRerate = false })
    }

    ScreenScaffold(
        title = stringResource(R.string.event_title),
        onBack = { nav.popBackStack() },
        actions = {
            detail?.event?.let { e ->
                ViewOriginal(e) { open -> IconButton(onClick = open) { Icon(Icons.Filled.OpenInBrowser, contentDescription = stringResource(R.string.event_view_original)) } }
            }
            IconButton(onClick = { confirmRerate = true }) { Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.event_rerate)) }
        },
    ) { modifier ->
        val d = detail
        if (d == null) {
            if (error != null) ErrorState(error!!, onRetry = { vm.load() }, modifier = modifier) else LoadingBox(modifier)
            return@ScreenScaffold
        }
        val e: Event = d.event
        Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Avatar(e.author?.pictureUrl, size = 40.dp)
                    Column(Modifier.weight(1f)) {
                        Text(e.author?.name ?: sourceLabel(e.sourceName, e.sourceType), style = MaterialTheme.typography.titleSmall)
                        Text(Times.dateTime(e.publishedAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Tag(stringResource(R.string.events_from_source, sourceLabel(e.sourceName, e.sourceType)))
                    eventTypeLabel(e.eventType)?.let { Tag(it) }
                }
                NostrContentView(e, collapsible = false)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ViewOriginal(e) { open -> TextButton(onClick = open) { Text(stringResource(R.string.event_view_original)) } }
                    e.externalId?.let { ext ->
                        TextButton(onClick = { Links.copy(context, "id", ext) }) {
                            Icon(Icons.Filled.ContentCopy, contentDescription = null)
                            Text(stringResource(R.string.common_copy), modifier = Modifier.padding(start = 6.dp))
                        }
                    }
                }
            }

            SectionCard(stringResource(R.string.event_channel_relevance)) {
                val ratings = d.channelEvents.sortedByDescending { it.relevanceScore ?: -1 }
                if (ratings.isEmpty()) {
                    Hint(stringResource(R.string.event_not_rated))
                    Button(onClick = { vm.rerate() }) { Text(stringResource(R.string.event_rate_all_channels)) }
                } else {
                    val selectable = ratings.filterNot { it.used }.map { it.id }
                    if (selectable.isNotEmpty()) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { vm.selectAll(selectable) }, verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(selected.containsAll(selectable), onCheckedChange = null)
                            Text(stringResource(R.string.event_select_all), modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                    ratings.forEach { ce -> RatingRow(ce, ce.id in selected, onToggle = { vm.toggle(ce.id) }, onOpenChannel = { nav.navigate(Routes.channel(ce.channelId, selectedEvent = d.event.id)) }) }
                    if (selectable.isNotEmpty()) {
                        Button(onClick = { vm.markUsed() }, enabled = selected.isNotEmpty()) { Text(stringResource(R.string.event_mark_used_selected)) }
                    }
                }
            }

            if (d.linkedContents.isNotEmpty()) {
                SectionCard(stringResource(R.string.linked_content)) {
                    d.linkedContents.forEach { link ->
                        Column(Modifier.fillMaxWidth().clickable { Links.openUrl(context, link.url) }.padding(vertical = 6.dp)) {
                            Text(link.title ?: link.url, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                            link.summary?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RatingRow(ce: ChannelEvent, checked: Boolean, onToggle: () -> Unit, onOpenChannel: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (ce.used) {
                Checkbox(true, onCheckedChange = null, enabled = false)
            } else {
                Checkbox(checked, onCheckedChange = { onToggle() })
            }
            Text(
                ce.channelName.orEmpty(), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f).clickable(onClick = onOpenChannel).padding(vertical = 8.dp),
            )
            if (ce.used) Tag(stringResource(R.string.channel_used))
            RelevanceChip(ce.relevanceScore, Modifier.padding(start = 6.dp))
        }
        if (ce.used) Hint(stringResource(R.string.event_already_used), Modifier.padding(start = 48.dp))
        ce.relevanceReason?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, fontStyle = FontStyle.Italic, modifier = Modifier.padding(start = 48.dp))
        }
        ce.engine?.let { engine ->
            Hint(
                stringResource(if (engine == "decision") R.string.settings_engine_decision_label else R.string.settings_engine_chat_label),
                Modifier.padding(start = 48.dp),
            )
        }
    }
}

// ---------------------------------------------------------------- manual

class ManualEventViewModel(private val container: AppContainer) : ViewModel() {
    val saving = MutableStateFlow(false)
    val created = MutableStateFlow<Long?>(null)
    val errors = MutableStateFlow<List<String>>(emptyList())

    fun save(content: String) {
        saving.value = true
        errors.value = emptyList()
        viewModelScope.launch {
            apiCall { container.api.createManualEvent(ManualEventBody(content)) }
                .onSuccess { r ->
                    container.messages.text(r.notice)
                    r.event?.let { container.dao.upsertEvents(listOf(EventEntity.from(it))) }
                    container.sync.sync()
                    created.value = r.event?.id ?: -1
                }
                .onFailure { if (it is ApiError.Validation && it.details.isNotEmpty()) errors.value = it.allMessages else container.messages.error(it) }
            saving.value = false
        }
    }
}

@Composable
fun ManualEventScreen(nav: NavController) {
    val vm = appViewModel { ManualEventViewModel(it) }
    val saving by vm.saving.collectAsState()
    val created by vm.created.collectAsState()
    val errors by vm.errors.collectAsState()
    var content by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(created) { if (created != null) nav.popBackStack() }
    ScreenScaffold(title = stringResource(R.string.manual_title), onBack = { nav.popBackStack() }) { modifier ->
        Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Hint(stringResource(R.string.manual_subtitle))
            OutlinedTextField(
                content, { content = it },
                label = { Text(stringResource(R.string.manual_content)) },
                placeholder = { Text(stringResource(R.string.manual_placeholder)) },
                isError = errors.isNotEmpty(),
                minLines = 10, modifier = Modifier.fillMaxWidth().heightIn(min = 200.dp),
            )
            errors.forEach { Text(it, color = MaterialTheme.colorScheme.error) }
            BusyButton(stringResource(R.string.manual_submit), onClick = { vm.save(content) }, busy = saving, enabled = content.isNotBlank(), modifier = Modifier.fillMaxWidth())
        }
    }
}

/**
 * "View original": the nostr apps installed on this phone (through the event's
 * NIP-21 link) and the web link from the user's settings. With only one of
 * them, [trigger] opens it directly; otherwise it offers the choice.
 */
@Composable
private fun ViewOriginal(event: Event, trigger: @Composable (open: () -> Unit) -> Unit) {
    val context = LocalContext.current
    val nostrUri = event.nostrUri
    val webUrl = event.sourceUrl
    val apps = remember(nostrUri) { nostrUri?.let { Links.nostrApps(context, it) }.orEmpty() }
    if (apps.isEmpty() && webUrl == null) return
    var menu by remember { mutableStateOf(false) }
    Box {
        trigger {
            when {
                apps.isEmpty() -> Links.openUrl(context, webUrl!!)
                apps.size == 1 && webUrl == null -> Links.openInApp(context, nostrUri!!, apps.single().packageName)
                else -> menu = true
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            apps.forEach { app ->
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.event_open_in_app, app.label)) },
                    onClick = { menu = false; Links.openInApp(context, nostrUri!!, app.packageName) },
                )
            }
            if (webUrl != null) {
                val host = remember(webUrl) { android.net.Uri.parse(webUrl).host?.removePrefix("www.") ?: webUrl }
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.event_open_on_web, host)) },
                    onClick = { menu = false; Links.openUrl(context, webUrl) },
                )
            }
        }
    }
}
