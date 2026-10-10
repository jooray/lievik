package today.cypherpunk.lievik.ui.screens.sources

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.Source
import today.cypherpunk.lievik.data.api.SourceBody
import today.cypherpunk.lievik.data.api.SourceForm
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.db.EventEntity
import today.cypherpunk.lievik.ui.components.Avatar
import today.cypherpunk.lievik.ui.components.BusyButton
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.EventCard
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.components.sourceLabel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.util.Links

class SourcesViewModel(private val container: AppContainer) : ViewModel() {
    val sources = container.dao.sources().map { rows -> rows.map { it.toModel() }.filter { it.sourceType != "manual" } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)
    val refreshing = MutableStateFlow(false)

    fun sync() = viewModelScope.launch {
        refreshing.value = true
        container.sync.sync()
        refreshing.value = false
    }

    fun refreshAll() = viewModelScope.launch {
        apiCall { container.api.refreshAllSources() }
            .onSuccess { container.messages.text(it.notice) }
            .onFailure { container.messages.error(it) }
    }

    fun refresh(id: Long) = viewModelScope.launch {
        apiCall { container.api.refreshSource(id) }
            .onSuccess { container.messages.text(it.notice) }
            .onFailure { container.messages.error(it) }
    }
}

@Composable
fun sourceTypeLabel(type: String): String = when (type) {
    "rss" -> stringResource(R.string.source_type_rss)
    "manual" -> stringResource(R.string.source_type_manual)
    else -> stringResource(R.string.source_type_nostr)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SourcesScreen(nav: NavController) {
    val vm = appViewModel { SourcesViewModel(it) }
    val sources by vm.sources.collectAsState()
    val refreshing by vm.refreshing.collectAsState()
    ScreenScaffold(
        title = stringResource(R.string.sources_title),
        onBack = { nav.popBackStack() },
        actions = {
            if (!sources.isNullOrEmpty()) {
                IconButton(onClick = { vm.refreshAll() }) { Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.sources_refresh_all)) }
            }
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { nav.navigate(Routes.SOURCE_NEW) },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text(stringResource(R.string.sources_add_source)) },
            )
        },
    ) { modifier ->
        PullToRefreshBox(refreshing, onRefresh = { vm.sync() }, modifier = modifier) {
            val list = sources
            when {
                list == null -> LoadingBox()
                list.isEmpty() -> EmptyState(stringResource(R.string.sources_empty_title), stringResource(R.string.sources_empty_hint))
                else -> LazyColumn(contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    item { Hint(stringResource(R.string.sources_subtitle)) }
                    items(list, key = { it.id }) { source ->
                        SourceRow(source, onOpen = { nav.navigate(Routes.source(source.id)) }, onRefresh = { vm.refresh(source.id) })
                    }
                }
            }
        }
    }
}

@Composable
private fun SourceRow(source: Source, onOpen: () -> Unit, onRefresh: () -> Unit) {
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(1.dp),
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (source.sourceType == "rss") Icon(Icons.Filled.RssFeed, contentDescription = null, modifier = Modifier.padding(6.dp))
            else Avatar(null, size = 36.dp)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(sourceLabel(source.name, source.sourceType), style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                source.identifier?.let { Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Tag(sourceTypeLabel(source.sourceType))
                    Tag(stringResource(R.string.sources_distance, source.distance.toString()))
                    Tag(pluralStringResource(R.plurals.sources_events, source.eventCount, source.eventCount))
                }
            }
            IconButton(onClick = onRefresh) { Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.refresh)) }
        }
    }
}

// ---------------------------------------------------------------- one source

class SourceViewModel(private val container: AppContainer, private val id: Long) : ViewModel() {
    val source = container.dao.source(id).map { it?.toModel() }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)
    val limit = MutableStateFlow(100)
    val events = container.dao.sourceEvents(id, 500).map { rows -> rows.map(EventEntity::toModel) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        // Older events may predate the sync window: page 1 from the server fills the cache.
        viewModelScope.launch {
            apiCall { container.api.sourceEvents(id, 1) }.onSuccess { r ->
                container.dao.upsertEvents(r.events.map(EventEntity::from))
            }
        }
    }

    fun refresh() = viewModelScope.launch {
        apiCall { container.api.refreshSource(id) }
            .onSuccess { container.messages.text(it.notice) }
            .onFailure { container.messages.error(it) }
    }
}

@Composable
fun SourceScreen(id: Long, nav: NavController) {
    val vm = appViewModel(key = "source-$id") { SourceViewModel(it, id) }
    val source by vm.source.collectAsState()
    val events by vm.events.collectAsState()
    val context = LocalContext.current
    ScreenScaffold(
        title = source?.let { sourceLabel(it.name, it.sourceType) } ?: "",
        onBack = { nav.popBackStack() },
        actions = {
            IconButton(onClick = { vm.refresh() }) { Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.refresh)) }
            IconButton(onClick = { nav.navigate(Routes.sourceEdit(id)) }) { Icon(Icons.Filled.Edit, contentDescription = stringResource(R.string.common_edit)) }
        },
    ) { modifier ->
        LazyColumn(modifier, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            source?.let { s ->
                item {
                    SectionCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Tag(sourceTypeLabel(s.sourceType))
                            Tag(stringResource(R.string.sources_distance, s.distance.toString()))
                            Tag(pluralStringResource(R.plurals.sources_events, s.eventCount, s.eventCount))
                        }
                        s.identifier?.let { identifier ->
                            Text(
                                identifier,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.clickable { Links.copy(context, "identifier", identifier) },
                            )
                            Hint(stringResource(R.string.sources_click_to_copy))
                        }
                        s.description?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                    }
                }
            }
            item { Text(stringResource(R.string.source_show_events), style = MaterialTheme.typography.titleMedium) }
            if (events.isEmpty()) item { EmptyState(stringResource(R.string.source_show_empty)) }
            items(events, key = { it.id }) { event -> EventCard(event, showTopChannels = true, onOpen = { nav.navigate(Routes.event(event.id)) }) }
        }
    }
}

// ---------------------------------------------------------------- add / edit

data class SourceDraft(
    val sourceType: String = "nostr",
    val identifier: String = "",
    val name: String = "",
    val description: String = "",
    val distance: Int = 5,
    val includeReplies: Boolean = false,
    val includeReposts: Boolean = false,
    val importDays: String = "30",
)

class SourceEditViewModel(private val container: AppContainer, private val id: Long?) : ViewModel() {
    val draft = MutableStateFlow<SourceDraft?>(if (id == null) SourceDraft() else null)
    val saving = MutableStateFlow(false)
    val errors = MutableStateFlow<Map<String, List<String>>>(emptyMap())
    val done = MutableStateFlow(false)
    val deleted = MutableStateFlow(false)

    init {
        if (id != null) viewModelScope.launch {
            val cached = container.dao.source(id).firstOrNull()?.toModel()
            cached?.let { draft.value = it.toDraft() }
            apiCall { container.api.source(id) }.onSuccess { r -> r.source?.let { draft.value = it.toDraft() } }
                .onFailure { if (cached == null) container.messages.error(it) }
        }
    }

    private fun Source.toDraft() = SourceDraft(
        sourceType, identifier.orEmpty(), name.orEmpty(), description.orEmpty(), distance,
        settings.includeReplies, settings.includeReposts, settings.importDays.toString(),
    )

    fun update(change: (SourceDraft) -> SourceDraft) {
        draft.value = draft.value?.let(change)
    }

    fun save() {
        val d = draft.value ?: return
        saving.value = true
        errors.value = emptyMap()
        val body = SourceBody(
            SourceForm(
                sourceType = d.sourceType, identifier = d.identifier.trim(), name = d.name.trim(), description = d.description.trim(),
                distance = d.distance, settingsIncludeReplies = d.includeReplies, settingsIncludeReposts = d.includeReposts,
                settingsImportDays = d.importDays.toIntOrNull() ?: 30,
            ),
        )
        viewModelScope.launch {
            apiCall { if (id == null) container.api.createSource(body) else container.api.updateSource(id, body) }
                .onSuccess {
                    container.messages.text(it.notice)
                    container.sync.sync()
                    done.value = true
                }
                .onFailure {
                    if (it is ApiError.Validation && it.details.isNotEmpty()) errors.value = it.details else container.messages.error(it)
                }
            saving.value = false
        }
    }

    fun delete() {
        val sourceId = id ?: return
        viewModelScope.launch {
            apiCall { container.api.deleteSource(sourceId) }
                .onSuccess {
                    if (it.notice != null) container.messages.text(it.notice) else container.messages.res(R.string.source_removed)
                    container.sync.sync()
                    deleted.value = true
                    done.value = true
                }
                .onFailure { container.messages.error(it) }
        }
    }
}

@Composable
fun SourceEditScreen(id: Long?, nav: NavController) {
    val vm = appViewModel(key = "source-edit-$id") { SourceEditViewModel(it, id) }
    val draft by vm.draft.collectAsState()
    val saving by vm.saving.collectAsState()
    val errors by vm.errors.collectAsState()
    val done by vm.done.collectAsState()
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(done) {
        if (done) {
            if (vm.deleted.value) nav.popBackStack(Routes.SOURCES, inclusive = false) else nav.popBackStack()
        }
    }
    if (confirmDelete) {
        ConfirmDialog(stringResource(R.string.source_confirm_delete), stringResource(R.string.source_delete), onConfirm = {
            vm.delete()
        }, onDismiss = { confirmDelete = false }, destructive = true)
    }
    ScreenScaffold(
        title = stringResource(if (id == null) R.string.source_new_title else R.string.source_edit_title),
        onBack = { nav.popBackStack() },
    ) { modifier ->
        val d = draft
        if (d == null) {
            LoadingBox(modifier)
            return@ScreenScaffold
        }
        Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (id == null) {
                Hint(stringResource(R.string.source_new_subtitle))
                Text(stringResource(R.string.source_form_type), style = MaterialTheme.typography.titleSmall)
                listOf("nostr" to R.string.source_form_type_nostr, "rss" to R.string.source_form_type_rss).forEach { (type, label) ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(d.sourceType == type, role = Role.RadioButton) { vm.update { it.copy(sourceType = type) } },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = d.sourceType == type, onClick = null)
                        Text(stringResource(label), modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
            val nostr = d.sourceType == "nostr"
            FieldWithErrors(errors["identifier"]) {
                OutlinedTextField(
                    d.identifier, { v -> vm.update { it.copy(identifier = v) } },
                    label = { Text(stringResource(if (nostr) R.string.source_form_nostr_label else R.string.source_form_rss_label)) },
                    supportingText = { Text(stringResource(if (nostr) R.string.source_form_nostr_hint else R.string.source_form_rss_hint)) },
                    singleLine = true, enabled = id == null || d.sourceType != "manual",
                    keyboardOptions = KeyboardOptions(keyboardType = if (nostr) KeyboardType.Ascii else KeyboardType.Uri),
                    isError = errors["identifier"] != null,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            FieldWithErrors(errors["name"]) {
                OutlinedTextField(
                    d.name, { v -> vm.update { it.copy(name = v) } },
                    label = { Text(stringResource(R.string.source_attr_name)) },
                    placeholder = { Text(stringResource(R.string.source_form_name_placeholder)) },
                    supportingText = { Text(stringResource(R.string.source_form_name_hint)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth(),
                )
            }
            OutlinedTextField(
                d.description, { v -> vm.update { it.copy(description = v) } },
                label = { Text(stringResource(R.string.source_attr_description)) },
                placeholder = { Text(stringResource(R.string.source_form_description_placeholder)) },
                minLines = 3, modifier = Modifier.fillMaxWidth(),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.source_form_distance), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                Tag(d.distance.toString())
            }
            Slider(
                value = d.distance.toFloat(), onValueChange = { v -> vm.update { it.copy(distance = v.toInt()) } },
                valueRange = 0f..10f, steps = 9,
            )
            Hint(stringResource(R.string.source_form_distance_hint))
            Text(stringResource(R.string.source_form_import_settings), style = MaterialTheme.typography.titleSmall)
            if (nostr) {
                CheckRow(stringResource(R.string.source_form_include_replies), d.includeReplies) { v -> vm.update { it.copy(includeReplies = v) } }
                CheckRow(stringResource(R.string.source_form_include_reposts), d.includeReposts) { v -> vm.update { it.copy(includeReposts = v) } }
            }
            FieldWithErrors(errors["settings_import_days"] ?: errors["import_days"]) {
                OutlinedTextField(
                    d.importDays, { v -> vm.update { it.copy(importDays = v.filter(Char::isDigit).take(4)) } },
                    label = { Text(stringResource(R.string.source_form_import_days)) },
                    supportingText = { Text(stringResource(R.string.source_form_import_days_hint)) },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            errors.filterKeys { it !in setOf("identifier", "name", "settings_import_days", "import_days") }.values.flatten().forEach {
                Text(it, color = MaterialTheme.colorScheme.error)
            }
            BusyButton(
                stringResource(if (id == null) R.string.source_form_create else R.string.source_form_update),
                onClick = { vm.save() }, busy = saving, enabled = d.identifier.isNotBlank(), modifier = Modifier.fillMaxWidth(),
            )
            if (id != null) {
                SectionCard(stringResource(R.string.source_danger_zone)) {
                    Hint(stringResource(R.string.source_danger_hint))
                    OutlinedButton(onClick = { confirmDelete = true }) {
                        Text(stringResource(R.string.source_delete), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }
}

@Composable
fun CheckRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { onChange(!checked) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked = checked, onCheckedChange = null)
        Text(label, modifier = Modifier.padding(start = 8.dp))
    }
}

@Composable
fun FieldWithErrors(messages: List<String>?, content: @Composable () -> Unit) {
    Column {
        content()
        messages?.forEach { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
    }
}
