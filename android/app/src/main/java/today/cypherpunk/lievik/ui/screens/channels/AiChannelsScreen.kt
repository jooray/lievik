package today.cypherpunk.lievik.ui.screens.channels

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
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
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.BulkCreateBody
import today.cypherpunk.lievik.data.api.ChannelSettings
import today.cypherpunk.lievik.data.api.Proposal
import today.cypherpunk.lievik.data.api.ProposalChannel
import today.cypherpunk.lievik.data.api.StreamEvent
import today.cypherpunk.lievik.data.api.TemplateBody
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.repo.Messages
import today.cypherpunk.lievik.ui.components.ChatBubble
import today.cypherpunk.lievik.ui.components.ChatInput
import today.cypherpunk.lievik.ui.components.ChatMessage
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.components.text
import today.cypherpunk.lievik.ui.nav.Routes

data class ProposalCard(val channel: ProposalChannel, val selected: Boolean = true, val expanded: Boolean = false)
data class TemplateCard(val template: TemplateBody, val selected: Boolean = true)

/** "AI Add Channels": a streamed chat whose proposals become editable cards. */
class AiChannelsViewModel(private val container: AppContainer) : ViewModel() {
    val messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val cards = MutableStateFlow<List<ProposalCard>>(emptyList())
    val templates = MutableStateFlow<List<TemplateCard>>(emptyList())
    val streaming = MutableStateFlow(false)
    val creating = MutableStateFlow(false)
    val created = MutableStateFlow(false)
    val channelCount = container.dao.channels().map { it.size }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)
    private var job: Job? = null

    fun send(text: String) {
        val message = text.trim()
        if (message.isEmpty()) return
        val history = messages.value.filterNot { it.error }
        messages.value = history + ChatMessage("user", message) + ChatMessage("assistant", "", streaming = true)
        streaming.value = true
        val body = buildJsonObject {
            put("message", message)
            put("history", buildJsonArray {
                history.forEach { add(buildJsonObject { put("role", it.role); put("content", JsonPrimitive(it.content)) }) }
            })
        }
        job = viewModelScope.launch {
            try {
                container.client.stream("channels/ai/stream", body).collect { event ->
                    when (event) {
                        is StreamEvent.Chunk -> appendAssistant(event.text)
                        is StreamEvent.ProposalReady -> setProposal(event.proposal)
                        is StreamEvent.Failed -> failAssistant(event.message)
                        is StreamEvent.Complete -> if (!event.success) event.errorMessage?.let { failAssistant(it) }
                        is StreamEvent.Phase -> {}
                    }
                }
            } catch (e: ApiError) {
                if (e.isBillingDenial) {
                    container.messages.show(Messages.forError(e))
                    messages.value = messages.value.dropLast(1)
                } else {
                    failAssistant(null, e)
                }
            } finally {
                messages.value = messages.value.map { if (it.streaming) it.copy(streaming = false) else it }
                streaming.value = false
            }
        }
    }

    private val errorMessages = MutableStateFlow<ApiError?>(null)
    val lastError = errorMessages

    private fun appendAssistant(text: String) {
        val list = messages.value.toMutableList()
        val last = list.lastOrNull() ?: return
        list[list.lastIndex] = last.copy(content = last.content + text)
        messages.value = list
    }

    private fun failAssistant(message: String?, error: ApiError? = null) {
        errorMessages.value = error
        val list = messages.value.toMutableList()
        val last = list.lastOrNull()
        val text = message ?: ""
        if (last != null && last.role == "assistant") list[list.lastIndex] = last.copy(content = text, streaming = false, error = true)
        messages.value = list
    }

    private fun setProposal(p: Proposal) {
        cards.value = p.channels.map { ProposalCard(it) }
        templates.value = p.templates.map { TemplateCard(it) }
    }

    fun stop() {
        job?.cancel()
    }

    fun clear() {
        stop()
        messages.value = emptyList()
        cards.value = emptyList()
        templates.value = emptyList()
    }

    fun updateCard(index: Int, change: (ProposalCard) -> ProposalCard) {
        cards.value = cards.value.mapIndexed { i, c -> if (i == index) change(c) else c }
    }

    fun removeCard(index: Int) {
        cards.value = cards.value.filterIndexed { i, _ -> i != index }
    }

    fun updateTemplate(index: Int, change: (TemplateCard) -> TemplateCard) {
        templates.value = templates.value.mapIndexed { i, c -> if (i == index) change(c) else c }
    }

    fun create(onlySelected: Boolean) {
        val channels = cards.value.filter { !onlySelected || it.selected }.map { it.channel }.filter { it.name.isNotBlank() }
            .map { it.copy(contentLanguage = it.contentLanguage ?: it.language, settings = ChannelSettings(it.settings.relevanceThreshold.coerceIn(0, 100), true)) }
        if (channels.isEmpty()) {
            container.messages.res(R.string.ai_none_selected)
            return
        }
        val chosenTemplates = templates.value.filter { it.selected }.map { it.template }
        creating.value = true
        viewModelScope.launch {
            apiCall { container.api.bulkCreateChannels(BulkCreateBody(channels, chosenTemplates)) }
                .onSuccess {
                    container.messages.text(it.notice)
                    container.sync.sync()
                    created.value = true
                }
                .onFailure { container.messages.error(it) }
            creating.value = false
        }
    }
}

@Composable
fun AiChannelsScreen(nav: NavController) {
    val vm = appViewModel { AiChannelsViewModel(it) }
    val messages by vm.messages.collectAsState()
    val cards by vm.cards.collectAsState()
    val templates by vm.templates.collectAsState()
    val streaming by vm.streaming.collectAsState()
    val creating by vm.creating.collectAsState()
    val created by vm.created.collectAsState()
    val count by vm.channelCount.collectAsState()
    val lastError by vm.lastError.collectAsState()
    var input by rememberSaveable { mutableStateOf("") }
    val listState = rememberLazyListState()

    LaunchedEffect(created) { if (created) nav.popBackStack(Routes.CHANNELS, inclusive = false) }
    LaunchedEffect(messages.size, messages.lastOrNull()?.content?.length, cards.size) {
        val total = listState.layoutInfo.totalItemsCount
        if (total > 0) listState.animateScrollToItem(total - 1)
    }

    ScreenScaffold(
        title = stringResource(R.string.ai_title),
        onBack = { nav.popBackStack() },
        actions = {
            if (messages.isNotEmpty()) IconButton(onClick = { vm.clear() }) { Icon(Icons.Filled.DeleteSweep, contentDescription = stringResource(R.string.ai_clear_chat)) }
        },
    ) { modifier ->
        Column(modifier) {
            LazyColumn(Modifier.weight(1f).fillMaxSize(), state = listState, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Hint(stringResource(R.string.ai_subtitle))
                        Hint(pluralStringResource(R.plurals.ai_existing, count, count))
                    }
                }
                if (messages.isEmpty()) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(stringResource(R.string.ai_welcome), style = MaterialTheme.typography.bodyMedium)
                            listOf(R.string.ai_example_1, R.string.ai_example_2, R.string.ai_example_3).forEach { ex ->
                                val example = stringResource(ex)
                                OutlinedButton(onClick = { input = example.trim('“', '”', '"') }, modifier = Modifier.fillMaxWidth()) { Text(example) }
                            }
                        }
                    }
                }
                itemsIndexed(messages) { _, m ->
                    val shown = if (m.error && m.content.isBlank()) {
                        m.copy(content = lastError?.let { Messages.forError(it).text() } ?: stringResource(R.string.ai_error))
                    } else if (m.role == "assistant" && cards.isNotEmpty()) {
                        m.copy(content = stripJsonBlocks(m.content))
                    } else m
                    ChatBubble(shown, stringResource(R.string.ai_thinking))
                }
                if (cards.isNotEmpty()) {
                    item { Text(stringResource(R.string.ai_proposed_channels, cards.size), style = MaterialTheme.typography.titleMedium) }
                    itemsIndexed(cards) { index, card -> ProposalCardView(card, onChange = { vm.updateCard(index, it) }, onRemove = { vm.removeCard(index) }) }
                    if (templates.isNotEmpty()) {
                        item { Text(stringResource(R.string.ai_new_templates), style = MaterialTheme.typography.titleSmall) }
                        itemsIndexed(templates) { index, t ->
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.heightIn(min = 48.dp)) {
                                Checkbox(t.selected, onCheckedChange = { v -> vm.updateTemplate(index) { it.copy(selected = v) } })
                                Text(t.template.name)
                            }
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { vm.create(onlySelected = true) }, enabled = !creating && cards.any { it.selected }) { Text(stringResource(R.string.ai_create_selected)) }
                            OutlinedButton(onClick = { vm.create(onlySelected = false) }, enabled = !creating) { Text(stringResource(R.string.ai_create_all)) }
                        }
                    }
                }
            }
            ChatInput(
                input, { input = it }, stringResource(R.string.ai_placeholder), streaming,
                onSend = { vm.send(input); input = "" }, onStop = { vm.stop() },
            )
        }
    }
}

private val JSON_FENCE = Regex("```(?:json)?\\s*\\{[\\s\\S]*?```")

/** The proposal JSON already shows as cards; keep only the prose around it. */
fun stripJsonBlocks(text: String): String = JSON_FENCE.replace(text, "").trim()

@Composable
private fun ProposalCardView(card: ProposalCard, onChange: ((ProposalCard) -> ProposalCard) -> Unit, onRemove: () -> Unit) {
    val c = card.channel
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), elevation = CardDefaults.cardElevation(1.dp)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(card.selected, onCheckedChange = { v -> onChange { it.copy(selected = v) } })
                Text(c.name, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                c.language?.let { Tag(it.uppercase()) }
                IconButton(onClick = { onChange { it.copy(expanded = !it.expanded) } }) {
                    Icon(if (card.expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = stringResource(R.string.ai_expand))
                }
                IconButton(onClick = onRemove) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.ai_remove)) }
            }
            Text(c.description?.takeIf { it.isNotBlank() } ?: stringResource(R.string.ai_no_description), style = MaterialTheme.typography.bodySmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                c.suggestedTemplate?.let { Tag(it) }
                Tag(stringResource(R.string.ai_threshold, c.settings.relevanceThreshold.toString()))
                c.contentStyle?.takeIf { it.isNotBlank() }?.let { Tag(stringResource(R.string.ai_style, it)) }
            }
            if (card.expanded) {
                fun edit(change: (ProposalChannel) -> ProposalChannel) = onChange { it.copy(channel = change(it.channel)) }
                OutlinedTextField(c.name, { v -> edit { it.copy(name = v) } }, label = { Text(stringResource(R.string.channel_attr_name)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(c.description.orEmpty(), { v -> edit { it.copy(description = v) } }, label = { Text(stringResource(R.string.channel_attr_description)) }, modifier = Modifier.fillMaxWidth())
                LanguagePicker(c.language ?: "en", onPick = { v -> edit { it.copy(language = v, contentLanguage = v) } })
                OutlinedTextField(c.contentStyle.orEmpty(), { v -> edit { it.copy(contentStyle = v) } }, label = { Text(stringResource(R.string.ai_content_style)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    c.settings.relevanceThreshold.toString(),
                    { v -> edit { it.copy(settings = it.settings.copy(relevanceThreshold = v.filter(Char::isDigit).take(3).toIntOrNull()?.coerceIn(0, 100) ?: 0)) } },
                    label = { Text(stringResource(R.string.ai_relevance_threshold)) },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    c.prompt.orEmpty(), { v -> edit { it.copy(prompt = v) } },
                    label = { Text(stringResource(R.string.ai_relevance_criteria)) },
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    minLines = 6, modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}
