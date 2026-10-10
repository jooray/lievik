package today.cypherpunk.lievik.ui.screens.content

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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.ChannelContent
import today.cypherpunk.lievik.data.api.ContentCreateBody
import today.cypherpunk.lievik.data.api.ContentForm
import today.cypherpunk.lievik.data.api.ContentUpdateBody
import today.cypherpunk.lievik.data.api.Event
import today.cypherpunk.lievik.data.api.StreamEvent
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.db.ContentEntity
import today.cypherpunk.lievik.data.db.EventEntity
import today.cypherpunk.lievik.data.repo.Messages
import today.cypherpunk.lievik.ui.components.BusyButton
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.ErrorState
import today.cypherpunk.lievik.ui.components.EventCard
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.Load
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.MarkdownText
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.util.Links
import today.cypherpunk.lievik.util.Times

// ---------------------------------------------------------------- library

class ContentListViewModel(private val container: AppContainer, private val channelId: Long) : ViewModel() {
    val contents = container.dao.contents(channelId).map { rows -> rows.map(ContentEntity::toModel) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)
    val refreshing = MutableStateFlow(false)
    val error = MutableStateFlow<ApiError?>(null)

    init { refresh() }

    fun refresh() = viewModelScope.launch {
        refreshing.value = true
        apiCall { container.api.contents(channelId) }
            .onSuccess { r ->
                error.value = null
                container.dao.replaceContents(channelId, (r.drafts + r.published).map { ContentEntity.from(it.copy(channelId = channelId)) })
            }
            .onFailure { error.value = it as ApiError }
        refreshing.value = false
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContentListScreen(channelId: Long, nav: NavController) {
    val vm = appViewModel(key = "contents-$channelId") { ContentListViewModel(it, channelId) }
    val contents by vm.contents.collectAsState()
    val refreshing by vm.refreshing.collectAsState()
    val error by vm.error.collectAsState()
    ScreenScaffold(title = stringResource(R.string.content_index_heading), onBack = { nav.popBackStack() }) { modifier ->
        PullToRefreshBox(refreshing, onRefresh = { vm.refresh() }, modifier = modifier) {
            val list = contents
            when {
                list == null -> LoadingBox()
                list.isEmpty() && error != null -> ErrorState(error!!, onRetry = { vm.refresh() })
                list.isEmpty() -> EmptyState(stringResource(R.string.content_empty), stringResource(R.string.content_empty_hint))
                else -> LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val drafts = list.filter { it.status != "published" }
                    val published = list.filter { it.status == "published" }
                    if (drafts.isNotEmpty()) {
                        item { Text(stringResource(R.string.content_drafts), style = MaterialTheme.typography.titleMedium) }
                        items(drafts, key = { it.id }) { c -> ContentRow(c, draft = true) { nav.navigate(Routes.content(channelId, c.id)) } }
                    }
                    if (published.isNotEmpty()) {
                        item { Text(stringResource(R.string.content_published_heading), style = MaterialTheme.typography.titleMedium) }
                        items(published, key = { it.id }) { c -> ContentRow(c, draft = false) { nav.navigate(Routes.content(channelId, c.id)) } }
                    }
                }
            }
        }
    }
}

@Composable
private fun ContentRow(content: ChannelContent, draft: Boolean, onOpen: () -> Unit) {
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(1.dp),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                content.title?.takeIf { it.isNotBlank() } ?: stringResource(if (draft) R.string.content_untitled_draft else R.string.content_untitled),
                style = MaterialTheme.typography.titleSmall,
            )
            content.content?.takeIf { it.isNotBlank() }?.let {
                Text(it, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Tag(pluralStringResource(R.plurals.content_source_events, content.eventIds.size, content.eventIds.size))
                Tag(Times.relative(if (draft) content.updatedAt else content.publishedAt ?: content.updatedAt))
            }
        }
    }
}

// ---------------------------------------------------------------- new

class ContentNewViewModel(private val container: AppContainer, private val channelId: Long, private val ids: List<Long>) : ViewModel() {
    val events = MutableStateFlow<List<Event>>(emptyList())
    val saving = MutableStateFlow(false)
    val created = MutableStateFlow<Long?>(null)

    init {
        viewModelScope.launch { events.value = container.dao.eventsByIds(ids).map(EventEntity::toModel) }
    }

    fun create(title: String, prompt: String) {
        saving.value = true
        viewModelScope.launch {
            apiCall { container.api.createContent(channelId, ContentCreateBody(ContentForm(title = title.trim(), generationPrompt = prompt.trim()), ids)) }
                .onSuccess { r ->
                    container.messages.text(r.notice)
                    r.content?.let { container.dao.upsertContents(listOf(ContentEntity.from(it.copy(channelId = channelId)))) }
                    created.value = r.content?.id
                }
                .onFailure { container.messages.error(it) }
            saving.value = false
        }
    }
}

@Composable
fun ContentNewScreen(channelId: Long, eventIds: List<Long>, nav: NavController) {
    val vm = appViewModel(key = "content-new-$channelId-${eventIds.joinToString()}") { ContentNewViewModel(it, channelId, eventIds) }
    val events by vm.events.collectAsState()
    val saving by vm.saving.collectAsState()
    val created by vm.created.collectAsState()
    var title by rememberSaveable { mutableStateOf("") }
    var prompt by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(created) {
        created?.let { id -> nav.navigate(Routes.content(channelId, id, generate = true)) { popUpTo(Routes.CHANNEL) } }
    }
    ScreenScaffold(title = stringResource(R.string.content_new_heading), onBack = { nav.popBackStack() }) { modifier ->
        if (eventIds.isEmpty()) {
            EmptyState(stringResource(R.string.content_new_no_events), modifier = modifier)
            return@ScreenScaffold
        }
        LazyColumn(modifier, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Hint(pluralStringResource(R.plurals.content_new_subtitle, eventIds.size, eventIds.size)) }
            item {
                OutlinedTextField(
                    title, { title = it }, label = { Text(stringResource(R.string.content_title_label)) },
                    placeholder = { Text(stringResource(R.string.content_new_title_placeholder)) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                OutlinedTextField(
                    prompt, { prompt = it }, label = { Text(stringResource(R.string.content_new_direction_label)) },
                    placeholder = { Text(stringResource(R.string.content_new_direction_placeholder)) },
                    supportingText = { Text(stringResource(R.string.content_new_direction_hint)) },
                    minLines = 3, modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                BusyButton(stringResource(R.string.content_new_submit), onClick = { vm.create(title, prompt) }, busy = saving, modifier = Modifier.fillMaxWidth())
            }
            item { Text(stringResource(R.string.content_new_selected_events, eventIds.size), style = MaterialTheme.typography.titleSmall) }
            items(events, key = { it.id }) { e -> EventCard(e, onOpen = { nav.navigate(Routes.event(e.id)) }) }
        }
    }
}

// ---------------------------------------------------------------- editor

data class EditorState(
    val content: ChannelContent,
    val events: List<Event>,
    val title: String,
    val body: String,
    val direction: String,
) {
    val dirty: Boolean
        get() = title != content.title.orEmpty() || body != content.content.orEmpty() || direction != content.generationPrompt.orEmpty()
}

/** Streaming status: which phase, and the text so far. */
data class StreamState(val active: Boolean = false, val phase: String? = null, val text: String = "", val refining: Boolean = false)

class ContentEditorViewModel(private val container: AppContainer, private val channelId: Long, private val id: Long) : ViewModel() {
    val load = MutableStateFlow<Load<Unit>>(Load.Loading)
    val state = MutableStateFlow<EditorState?>(null)
    val stream = MutableStateFlow(StreamState())
    val busy = MutableStateFlow(false)
    val deleted = MutableStateFlow(false)
    private var job: Job? = null

    init { reload() }

    fun reload(keepEdits: Boolean = false) = viewModelScope.launch {
        apiCall { container.api.content(channelId, id) }
            .onSuccess { r ->
                val c = r.content ?: return@onSuccess
                val previous = state.value
                state.value = EditorState(
                    c, r.events,
                    if (keepEdits && previous != null) previous.title else c.title.orEmpty(),
                    c.content.orEmpty(),
                    if (keepEdits && previous != null) previous.direction else c.generationPrompt.orEmpty(),
                )
                container.dao.upsertContents(listOf(ContentEntity.from(c.copy(channelId = channelId))))
                load.value = Load.Ready(Unit)
            }
            .onFailure { if (state.value == null) load.value = Load.Failed(it as ApiError) else container.messages.error(it) }
    }

    fun edit(change: (EditorState) -> EditorState) {
        state.value = state.value?.let(change)
    }

    fun save(then: (() -> Unit)? = null) {
        val s = state.value ?: return
        busy.value = true
        viewModelScope.launch {
            apiCall { container.api.updateContent(channelId, id, ContentUpdateBody(ContentForm(s.title, s.body, s.direction))) }
                .onSuccess { r ->
                    container.messages.text(r.notice)
                    r.content?.let { c -> state.value = s.copy(content = c, body = c.content.orEmpty()) }
                    then?.invoke()
                }
                .onFailure { container.messages.error(it) }
            busy.value = false
        }
    }

    fun generate() = runStream("channels/$channelId/contents/$id/generate", JsonObject(emptyMap()), refining = false)

    fun refine(instructions: String) {
        if (instructions.isBlank()) {
            container.messages.res(R.string.builder_instructions_required)
            return
        }
        runStream("channels/$channelId/contents/$id/refine", buildJsonObject { put("user_prompt", instructions.trim()) }, refining = true)
    }

    private fun runStream(path: String, body: JsonElement, refining: Boolean) {
        if (stream.value.active) return
        // Save a changed theme/direction first: generation reads it from the server.
        val s = state.value
        stream.value = StreamState(active = true, refining = refining)
        job = viewModelScope.launch {
            if (s != null && s.dirty) {
                apiCall { container.api.updateContent(channelId, id, ContentUpdateBody(ContentForm(s.title, s.body, s.direction))) }
            }
            var failed = false
            try {
                container.client.stream(path, body).collect { e ->
                    when (e) {
                        is StreamEvent.Phase -> stream.value = stream.value.copy(phase = e.phase, text = if (e.phase == "humanizing") "" else stream.value.text)
                        is StreamEvent.Chunk -> stream.value = stream.value.copy(text = stream.value.text + e.text)
                        is StreamEvent.Failed -> {
                            failed = true
                            if (e.message.isNullOrBlank()) container.messages.res(R.string.builder_generic_error) else container.messages.text(e.message)
                        }
                        is StreamEvent.Complete -> if (!e.success) { failed = true; e.errorMessage?.let { container.messages.text(it) } }
                        is StreamEvent.ProposalReady -> {}
                    }
                }
            } catch (e: ApiError) {
                failed = true
                container.messages.show(Messages.forError(e))
            } finally {
                stream.value = StreamState()
            }
            if (!failed) container.messages.res(if (refining) R.string.builder_refinement_complete else R.string.builder_generation_complete)
            reload(keepEdits = true)
        }
    }

    fun stop() {
        job?.cancel()
    }

    fun publish() = act { container.api.publishContent(channelId, id) }

    fun revert() = act { container.api.revertContent(channelId, id) }

    private fun act(call: suspend () -> today.cypherpunk.lievik.data.api.ContentResponse) {
        busy.value = true
        viewModelScope.launch {
            apiCall { call() }
                .onSuccess { r ->
                    container.messages.text(r.notice)
                    reload()
                    container.sync.sync()
                }
                .onFailure { container.messages.error(it) }
            busy.value = false
        }
    }

    fun delete() = viewModelScope.launch {
        apiCall { container.api.deleteContent(channelId, id) }
            .onSuccess {
                if (it.notice != null) container.messages.text(it.notice) else container.messages.res(R.string.content_deleted)
                container.dao.replaceContents(channelId, container.dao.contentsOnce(channelId).filter { c -> c.id != id })
                deleted.value = true
            }
            .onFailure { container.messages.error(it) }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ContentEditorScreen(channelId: Long, id: Long, autoGenerate: Boolean, nav: NavController) {
    val vm = appViewModel(key = "content-$id") { ContentEditorViewModel(it, channelId, id) }
    val load by vm.load.collectAsState()
    val state by vm.state.collectAsState()
    val stream by vm.stream.collectAsState()
    val busy by vm.busy.collectAsState()
    val deleted by vm.deleted.collectAsState()
    val context = LocalContext.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var refineText by rememberSaveable { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<String?>(null) }
    var generatedOnce by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(deleted) { if (deleted) nav.popBackStack() }
    LaunchedEffect(state != null) {
        val s = state ?: return@LaunchedEffect
        if (autoGenerate && !generatedOnce && s.body.isBlank()) {
            generatedOnce = true
            vm.generate()
        }
    }

    when (confirm) {
        "publish" -> ConfirmDialog(stringResource(R.string.content_publish_confirm), stringResource(R.string.content_publish), { vm.publish() }, { confirm = null })
        "revert" -> ConfirmDialog(stringResource(R.string.content_restore_confirm), stringResource(R.string.content_restore_previous), { vm.revert() }, { confirm = null })
        "delete" -> ConfirmDialog(stringResource(R.string.content_delete_confirm), stringResource(R.string.common_delete), { vm.delete() }, { confirm = null }, destructive = true)
    }

    val s = state
    val published = s?.content?.status == "published"
    ScreenScaffold(
        title = s?.content?.title?.takeIf { it.isNotBlank() }
            ?: stringResource(if (published) R.string.content_published_default_title else R.string.content_edit_default_title),
        onBack = { nav.popBackStack() },
        actions = {
            if (s != null) {
                IconButton(onClick = { Links.copy(context, s.title, s.body) }) {
                    Icon(Icons.Filled.ContentCopy, contentDescription = stringResource(R.string.content_copy_markdown))
                }
                IconButton(onClick = { Links.share(context, s.body, s.title) }) { Icon(Icons.Filled.Share, contentDescription = stringResource(R.string.share)) }
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.more_options)) }
                DropdownMenu(menu, onDismissRequest = { menu = false }) {
                    if (!published) DropdownMenuItem(text = { Text(stringResource(R.string.content_publish)) }, onClick = { menu = false; confirm = "publish" })
                    if (s.content.versionsCount > 0) DropdownMenuItem(text = { Text(stringResource(R.string.content_restore_previous)) }, onClick = { menu = false; confirm = "revert" })
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.common_delete)) },
                        leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
                        onClick = { menu = false; confirm = "delete" },
                    )
                }
            }
        },
    ) { modifier ->
        when (val l = load) {
            Load.Loading -> LoadingBox(modifier)
            is Load.Failed -> ErrorState(l.error, onRetry = { vm.reload() }, modifier = modifier)
            is Load.Ready -> if (s != null) Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Tag(stringResource(if (published) R.string.content_status_published else R.string.content_status_draft))
                    if (s.content.versionsCount > 0) Tag(pluralStringResource(R.plurals.content_versions_saved, s.content.versionsCount, s.content.versionsCount))
                    Tag(Times.relative(s.content.updatedAt))
                }
                OutlinedTextField(
                    s.title, { v -> vm.edit { it.copy(title = v) } },
                    label = { Text(stringResource(R.string.content_title_label)) },
                    placeholder = { Text(stringResource(R.string.content_title_placeholder)) },
                    singleLine = true, modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    s.direction, { v -> vm.edit { it.copy(direction = v) } },
                    label = { Text(stringResource(R.string.content_direction_heading)) },
                    placeholder = { Text(stringResource(R.string.content_direction_panel_placeholder)) },
                    minLines = 2, modifier = Modifier.fillMaxWidth(),
                )

                if (stream.active) {
                    SectionCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Text(
                                stringResource(
                                    when (stream.phase) {
                                        null -> R.string.builder_connecting
                                        "humanizing" -> R.string.builder_humanizing
                                        "refining" -> R.string.builder_refining
                                        else -> R.string.builder_generating
                                    },
                                ),
                                modifier = Modifier.padding(start = 12.dp).weight(1f),
                            )
                            TextButton(onClick = { vm.stop() }) { Text(stringResource(R.string.stop)) }
                        }
                        LinearProgressIndicator(Modifier.fillMaxWidth())
                        if (stream.text.isBlank()) Hint(stringResource(R.string.builder_appears_below))
                        else MarkdownText(stream.text)
                    }
                } else {
                    PrimaryTabRow(selectedTabIndex = tab) {
                        Tab(tab == 0, onClick = { tab = 0 }, text = { Text(stringResource(R.string.content_editor)) })
                        Tab(tab == 1, onClick = { tab = 1 }, text = { Text(stringResource(R.string.preview)) })
                    }
                    if (tab == 0) {
                        OutlinedTextField(
                            s.body, { v -> vm.edit { it.copy(body = v) } },
                            placeholder = { Text(stringResource(R.string.content_editor_placeholder)) },
                            textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                            minLines = 12, modifier = Modifier.fillMaxWidth().heightIn(min = 240.dp),
                        )
                    } else {
                        SectionCard { if (s.body.isBlank()) Hint(stringResource(R.string.content_editor_placeholder)) else MarkdownText(s.body) }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        BusyButton(
                            stringResource(if (published) R.string.builder_save_changes else R.string.content_save_draft),
                            onClick = { vm.save() }, busy = busy, enabled = s.dirty,
                        )
                        OutlinedButton(onClick = { vm.generate() }, enabled = !busy) {
                            Text(stringResource(if (s.body.isBlank()) R.string.content_generate else R.string.content_regenerate))
                        }
                        if (!published) Button(onClick = { if (s.dirty) vm.save { confirm = "publish" } else confirm = "publish" }, enabled = !busy && s.body.isNotBlank()) {
                            Text(stringResource(R.string.content_publish))
                        }
                    }
                    if (s.dirty) Hint(stringResource(R.string.unsaved_changes))
                    if (s.body.isNotBlank()) {
                        SectionCard(stringResource(R.string.content_ai_edit), subtitle = stringResource(R.string.content_ai_edit_hint)) {
                            OutlinedTextField(
                                refineText, { refineText = it },
                                placeholder = { Text(stringResource(R.string.content_refine_placeholder)) },
                                minLines = 2, modifier = Modifier.fillMaxWidth(),
                            )
                            Button(onClick = { vm.refine(refineText); refineText = "" }, enabled = refineText.isNotBlank()) {
                                Text(stringResource(R.string.content_apply_ai_edit))
                            }
                        }
                    }
                }
                if (s.content.versionsCount > 0) {
                    SectionCard(stringResource(R.string.content_version_history)) {
                        Hint(pluralStringResource(R.plurals.content_previous_versions, s.content.versionsCount, s.content.versionsCount))
                        OutlinedButton(onClick = { confirm = "revert" }, enabled = !busy && !stream.active) { Text(stringResource(R.string.content_restore_previous)) }
                    }
                }
                Text(stringResource(R.string.content_source_events_heading), style = MaterialTheme.typography.titleMedium)
                Hint(pluralStringResource(R.plurals.content_events_used, s.events.size, s.events.size))
                s.events.forEach { e -> EventCard(e, onOpen = { nav.navigate(Routes.event(e.id)) }) }
            }
        }
    }
}
