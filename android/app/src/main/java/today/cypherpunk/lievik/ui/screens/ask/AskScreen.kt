package today.cypherpunk.lievik.ui.screens.ask

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.ChatInfo
import today.cypherpunk.lievik.data.api.CitedEvent
import today.cypherpunk.lievik.data.api.StreamEvent
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.repo.Messages
import today.cypherpunk.lievik.ui.components.ChatBubble
import today.cypherpunk.lievik.ui.components.ChatInput
import today.cypherpunk.lievik.ui.components.ChatMessage
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.components.errorText
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.util.Times

data class AskTurn(val message: ChatMessage, val cited: List<CitedEvent> = emptyList(), val error: ApiError? = null)

/** "Ask Your Content": RAG chat over the indexed events, streamed. */
class AskViewModel(private val container: AppContainer) : ViewModel() {
    val info = MutableStateFlow<ChatInfo?>(null)
    val turns = MutableStateFlow<List<AskTurn>>(emptyList())
    val streaming = MutableStateFlow(false)
    private var job: Job? = null

    init {
        viewModelScope.launch { apiCall { container.api.chatInfo() }.onSuccess { info.value = it } }
    }

    fun ask(question: String) {
        val q = question.trim()
        if (q.isEmpty()) {
            container.messages.res(R.string.rag_question_required)
            return
        }
        val history = turns.value.filter { it.error == null && !it.message.error }.map { it.message }
        turns.value = turns.value + AskTurn(ChatMessage("user", q)) + AskTurn(ChatMessage("assistant", "", streaming = true))
        streaming.value = true
        val body = buildJsonObject {
            put("question", q)
            put("history", buildJsonArray {
                history.forEach { add(buildJsonObject { put("role", it.role); put("content", JsonPrimitive(it.content)) }) }
            })
        }
        job = viewModelScope.launch {
            try {
                container.client.stream("chat/stream", body).collect { e ->
                    when (e) {
                        is StreamEvent.Chunk -> updateLast { it.copy(message = it.message.copy(content = it.message.content + e.text)) }
                        is StreamEvent.Complete -> updateLast {
                            if (e.success) it.copy(cited = e.citedEvents) else it.copy(message = it.message.copy(content = e.errorMessage.orEmpty(), error = true))
                        }
                        is StreamEvent.Failed -> updateLast { it.copy(message = it.message.copy(content = e.message.orEmpty(), error = true)) }
                        else -> {}
                    }
                }
            } catch (e: ApiError) {
                if (e.isBillingDenial) {
                    container.messages.show(Messages.forError(e))
                    turns.value = turns.value.dropLast(2)
                } else {
                    updateLast { it.copy(message = it.message.copy(error = true), error = e) }
                }
            } finally {
                updateLast { it.copy(message = it.message.copy(streaming = false)) }
                streaming.value = false
            }
        }
    }

    private fun updateLast(change: (AskTurn) -> AskTurn) {
        val list = turns.value.toMutableList()
        if (list.isEmpty() || list.last().message.role != "assistant") return
        list[list.lastIndex] = change(list.last())
        turns.value = list
    }

    fun stop() {
        job?.cancel()
    }

    fun clear() {
        stop()
        turns.value = emptyList()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AskScreen(nav: NavController) {
    val vm = appViewModel { AskViewModel(it) }
    val info by vm.info.collectAsState()
    val turns by vm.turns.collectAsState()
    val streaming by vm.streaming.collectAsState()
    var input by rememberSaveable { mutableStateOf("") }
    val listState = rememberLazyListState()
    LaunchedEffect(turns.size, turns.lastOrNull()?.message?.content?.length) {
        val total = listState.layoutInfo.totalItemsCount
        if (total > 0) listState.animateScrollToItem(total - 1)
    }

    ScreenScaffold(
        title = stringResource(R.string.rag_heading),
        actions = {
            if (turns.isNotEmpty()) IconButton(onClick = { vm.clear() }) { Icon(Icons.Filled.DeleteSweep, contentDescription = stringResource(R.string.rag_clear_chat)) }
        },
    ) { modifier ->
        Column(modifier) {
            LazyColumn(Modifier.weight(1f).fillMaxSize(), state = listState, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Hint(stringResource(R.string.rag_intro))
                        info?.let { Hint(pluralStringResource(R.plurals.rag_indexed, it.totalCount, Times.number(it.embeddedCount), it.totalCount)) }
                    }
                }
                val i = info
                if (turns.isEmpty()) {
                    item {
                        if (i != null && i.embeddedCount == 0) {
                            EmptyState(stringResource(R.string.rag_empty_title))
                        } else {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(pluralStringResource(R.plurals.rag_welcome, i?.embeddedCount ?: 0, i?.embeddedCount ?: 0), style = MaterialTheme.typography.bodyMedium)
                                listOf(R.string.rag_example_topics, R.string.rag_example_summary, R.string.rag_example_person).forEach { ex ->
                                    val text = stringResource(ex)
                                    OutlinedButton(onClick = { input = text }, modifier = Modifier.fillMaxWidth()) { Text(text) }
                                }
                            }
                        }
                    }
                }
                itemsIndexed(turns) { _, turn ->
                    val shown = if (turn.message.error && turn.message.content.isBlank()) {
                        turn.message.copy(content = turn.error?.let { errorText(it) } ?: stringResource(R.string.rag_generic_error))
                    } else turn.message
                    ChatBubble(shown, stringResource(R.string.rag_thinking)) {
                        if (turn.cited.isNotEmpty()) {
                            Text(stringResource(R.string.rag_sources), style = MaterialTheme.typography.labelLarge)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                turn.cited.forEach { c ->
                                    AssistChip(
                                        onClick = { nav.navigate(Routes.event(c.id)) },
                                        label = {
                                            Text(
                                                listOfNotNull(c.sourceName ?: stringResource(R.string.source_label_unknown), Times.date(c.publishedAt).takeIf { it.isNotEmpty() })
                                                    .joinToString(" · "),
                                                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 220.dp),
                                            )
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
            ChatInput(input, { input = it }, stringResource(R.string.rag_placeholder), streaming, onSend = { vm.ask(input); input = "" }, onStop = { vm.stop() })
        }
    }
}
