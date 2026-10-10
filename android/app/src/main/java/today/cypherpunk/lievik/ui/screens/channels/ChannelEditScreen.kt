package today.cypherpunk.lievik.ui.screens.channels

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.Channel
import today.cypherpunk.lievik.data.api.ChannelBody
import today.cypherpunk.lievik.data.api.ChannelForm
import today.cypherpunk.lievik.data.api.ChannelSettings
import today.cypherpunk.lievik.data.api.ContentTemplate
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.data.db.ChannelEntity
import today.cypherpunk.lievik.ui.components.BusyButton
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.ui.screens.sources.FieldWithErrors

val CHANNEL_LANGUAGES = listOf("en", "sk", "cs", "de", "es", "fr", "pt", "it", "pl", "uk", "nl", "hu")

@Composable
fun languageName(code: String?): String = when (code) {
    "en" -> stringResource(R.string.lang_en)
    "sk" -> stringResource(R.string.lang_sk)
    "cs" -> stringResource(R.string.lang_cs)
    "de" -> stringResource(R.string.lang_de)
    "es" -> stringResource(R.string.lang_es)
    "fr" -> stringResource(R.string.lang_fr)
    "pt" -> stringResource(R.string.lang_pt)
    "it" -> stringResource(R.string.lang_it)
    "pl" -> stringResource(R.string.lang_pl)
    "uk" -> stringResource(R.string.lang_uk)
    "nl" -> stringResource(R.string.lang_nl)
    "hu" -> stringResource(R.string.lang_hu)
    else -> code.orEmpty()
}

data class ChannelDraft(
    val name: String = "",
    val description: String = "",
    val language: String = "en",
    val prompt: String = "",
    val contentPrompt: String = "",
    val contentLanguage: String = "",
    val contentStyle: String = "",
    val threshold: Int = 50,
    val humanize: Boolean = true,
) {
    companion object {
        fun of(c: Channel) = ChannelDraft(
            c.name, c.description.orEmpty(), c.language ?: "en", c.prompt.orEmpty(), c.contentPrompt.orEmpty(),
            c.contentLanguage.orEmpty(), c.contentStyle.orEmpty(), c.settings.relevanceThreshold, c.settings.humanizeOutput,
        )
    }
}

/**
 * The web's channel edit and settings forms combined (PATCH /channels/:id
 * takes both). A new channel gets the web's "new" form: name, description,
 * language and criteria, prefilled from GET /channels/new.
 */
class ChannelEditViewModel(private val container: AppContainer, private val id: Long?) : ViewModel() {
    val draft = MutableStateFlow<ChannelDraft?>(null)
    val templates = MutableStateFlow<List<ContentTemplate>>(emptyList())
    val saving = MutableStateFlow(false)
    val errors = MutableStateFlow<Map<String, List<String>>>(emptyMap())
    val result = MutableStateFlow<Long?>(null)
    val deleted = MutableStateFlow(false)

    init {
        viewModelScope.launch {
            if (id == null) {
                apiCall { container.api.newChannel() }
                    .onSuccess { r -> draft.value = r.channel?.let { ChannelDraft.of(it).copy(prompt = it.prompt ?: r.defaultPromptTemplate.orEmpty()) } ?: ChannelDraft(prompt = r.defaultPromptTemplate.orEmpty()) }
                    .onFailure { draft.value = ChannelDraft(); container.messages.error(it) }
            } else {
                val cached = container.dao.channel(id).firstOrNull()?.toModel()
                cached?.let { draft.value = ChannelDraft.of(it) }
                apiCall { container.api.channel(id) }
                    .onSuccess { r -> r.channel?.let { draft.value = ChannelDraft.of(it) } }
                    .onFailure { if (cached == null) { container.messages.error(it) } }
                apiCall { container.api.templates() }.onSuccess { templates.value = it.templates }
            }
        }
    }

    fun update(change: (ChannelDraft) -> ChannelDraft) {
        draft.value = draft.value?.let(change)
    }

    fun save() {
        val d = draft.value ?: return
        saving.value = true
        errors.value = emptyMap()
        viewModelScope.launch {
            val form = if (id == null) {
                ChannelForm(name = d.name.trim(), description = d.description.trim(), language = d.language, prompt = d.prompt)
            } else {
                ChannelForm(
                    name = d.name.trim(), description = d.description.trim(), language = d.language, prompt = d.prompt,
                    contentPrompt = d.contentPrompt, contentLanguage = d.contentLanguage.trim(), contentStyle = d.contentStyle.trim(),
                    settings = ChannelSettings(d.threshold, d.humanize),
                )
            }
            apiCall { if (id == null) container.api.createChannel(ChannelBody(form)) else container.api.updateChannel(id, ChannelBody(form)) }
                .onSuccess { r ->
                    container.messages.text(r.notice)
                    r.channel?.let { container.dao.upsertChannels(listOf(ChannelEntity.from(it))) }
                    container.sync.sync()
                    result.value = r.channel?.id ?: id ?: -1
                }
                .onFailure { if (it is ApiError.Validation && it.details.isNotEmpty()) errors.value = it.details else container.messages.error(it) }
            saving.value = false
        }
    }

    fun delete() {
        val channelId = id ?: return
        viewModelScope.launch {
            apiCall { container.api.deleteChannel(channelId) }
                .onSuccess {
                    if (it.notice != null) container.messages.text(it.notice) else container.messages.res(R.string.channel_deleted)
                    container.sync.sync()
                    deleted.value = true
                }
                .onFailure { container.messages.error(it) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ChannelEditScreen(id: Long?, nav: NavController) {
    val vm = appViewModel(key = "channel-edit-$id") { ChannelEditViewModel(it, id) }
    val draft by vm.draft.collectAsState()
    val templates by vm.templates.collectAsState()
    val saving by vm.saving.collectAsState()
    val errors by vm.errors.collectAsState()
    val result by vm.result.collectAsState()
    val deleted by vm.deleted.collectAsState()
    var confirmDelete by remember { mutableStateOf(false) }
    var pendingTemplate by remember { mutableStateOf<ContentTemplate?>(null) }

    LaunchedEffect(result) {
        val saved = result ?: return@LaunchedEffect
        if (id == null && saved > 0) {
            nav.navigate(Routes.channel(saved)) { popUpTo(Routes.CHANNELS) }
        } else {
            nav.popBackStack()
        }
    }
    LaunchedEffect(deleted) { if (deleted) nav.popBackStack(Routes.CHANNELS, inclusive = false) }

    if (confirmDelete) {
        ConfirmDialog(stringResource(R.string.channel_delete_confirm), stringResource(R.string.channel_delete), onConfirm = { vm.delete() }, onDismiss = { confirmDelete = false }, destructive = true)
    }
    pendingTemplate?.let { template ->
        ConfirmDialog(stringResource(R.string.template_replace_confirm), stringResource(android.R.string.ok), onConfirm = {
            vm.update { it.copy(contentPrompt = template.template) }
        }, onDismiss = { pendingTemplate = null })
    }

    ScreenScaffold(
        title = stringResource(if (id == null) R.string.channel_new_title else R.string.channel_edit_title),
        onBack = { nav.popBackStack() },
    ) { modifier ->
        val d = draft
        if (d == null) {
            LoadingBox(modifier)
            return@ScreenScaffold
        }
        Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Hint(if (id == null) stringResource(R.string.channel_new_subtitle) else stringResource(R.string.channel_edit_subtitle, d.name))
            FieldWithErrors(errors["name"]) {
                OutlinedTextField(
                    d.name, { v -> vm.update { it.copy(name = v) } },
                    label = { Text(stringResource(R.string.channel_attr_name)) },
                    placeholder = { Text(stringResource(R.string.channel_form_name_placeholder)) },
                    singleLine = true, isError = errors["name"] != null, modifier = Modifier.fillMaxWidth(),
                )
            }
            OutlinedTextField(
                d.description, { v -> vm.update { it.copy(description = v) } },
                label = { Text(stringResource(R.string.channel_attr_description)) },
                placeholder = { Text(stringResource(R.string.channel_form_description_placeholder)) },
                minLines = 2, modifier = Modifier.fillMaxWidth(),
            )
            LanguagePicker(d.language, onPick = { v -> vm.update { it.copy(language = v) } })
            Hint(stringResource(R.string.channel_form_language_hint))
            Text(stringResource(R.string.channel_form_criteria_label), style = MaterialTheme.typography.titleSmall)
            Hint(stringResource(R.string.channel_form_criteria_hint))
            FieldWithErrors(errors["prompt"]) {
                OutlinedTextField(
                    d.prompt, { v -> vm.update { it.copy(prompt = v) } },
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    minLines = 8, modifier = Modifier.fillMaxWidth().heightIn(min = 160.dp),
                )
            }

            if (id != null) {
                SectionCard(stringResource(R.string.channel_settings_title)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.channel_threshold_label), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                        Tag(stringResource(R.string.percent, d.threshold))
                    }
                    Hint(stringResource(R.string.channel_threshold_hint))
                    Slider(d.threshold.toFloat(), onValueChange = { v -> vm.update { it.copy(threshold = v.toInt()) } }, valueRange = 0f..100f, steps = 19)
                    Row {
                        Hint(stringResource(R.string.channel_show_everything), Modifier.weight(1f))
                        Hint(stringResource(R.string.channel_only_high))
                    }
                }
                SectionCard(stringResource(R.string.channel_generation_heading), subtitle = stringResource(R.string.channel_generation_hint)) {
                    OutlinedTextField(
                        d.contentLanguage, { v -> vm.update { it.copy(contentLanguage = v) } },
                        label = { Text(stringResource(R.string.channel_content_language)) },
                        placeholder = { Text(stringResource(R.string.channel_content_language_placeholder)) },
                        supportingText = { Text(stringResource(R.string.channel_content_language_hint)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        d.contentStyle, { v -> vm.update { it.copy(contentStyle = v) } },
                        label = { Text(stringResource(R.string.channel_writing_style)) },
                        placeholder = { Text(stringResource(R.string.channel_writing_style_placeholder)) },
                        supportingText = { Text(stringResource(R.string.channel_writing_style_hint)) },
                        minLines = 2, modifier = Modifier.fillMaxWidth(),
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.channel_humanize), style = MaterialTheme.typography.titleSmall)
                            Hint(stringResource(R.string.channel_humanize_hint))
                        }
                        Switch(d.humanize, onCheckedChange = { v -> vm.update { it.copy(humanize = v) } })
                    }
                    Text(stringResource(R.string.channel_formatting), style = MaterialTheme.typography.titleSmall)
                    Hint(stringResource(R.string.channel_formatting_hint))
                    if (templates.isNotEmpty()) {
                        Text(stringResource(R.string.channel_load_from_template), style = MaterialTheme.typography.labelLarge)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            templates.forEach { t ->
                                AssistChip(onClick = {
                                    if (d.contentPrompt.isBlank()) vm.update { it.copy(contentPrompt = t.template) } else pendingTemplate = t
                                }, label = { Text(t.name) })
                            }
                        }
                    } else {
                        Hint(stringResource(R.string.channel_create_templates_hint))
                    }
                    TextButton(onClick = { nav.navigate(Routes.TEMPLATES) }) { Text(stringResource(R.string.channel_manage_templates)) }
                    OutlinedTextField(
                        d.contentPrompt, { v -> vm.update { it.copy(contentPrompt = v) } },
                        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        minLines = 8, modifier = Modifier.fillMaxWidth().heightIn(min = 160.dp),
                    )
                }
            }
            errors.filterKeys { it !in setOf("name", "prompt") }.values.flatten().forEach { Text(it, color = MaterialTheme.colorScheme.error) }
            BusyButton(
                stringResource(if (id == null) R.string.channel_form_create else R.string.channel_form_update),
                onClick = { vm.save() }, busy = saving, enabled = d.name.isNotBlank(), modifier = Modifier.fillMaxWidth(),
            )
            if (id != null) {
                SectionCard(stringResource(R.string.channel_danger_zone)) {
                    Hint(stringResource(R.string.channel_danger_body))
                    OutlinedButton(onClick = { confirmDelete = true }) { Text(stringResource(R.string.channel_delete), color = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LanguagePicker(selected: String, onPick: (String) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    val options = if (selected in CHANNEL_LANGUAGES) CHANNEL_LANGUAGES else CHANNEL_LANGUAGES + selected
    ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = it }, modifier = modifier) {
        OutlinedTextField(
            value = "${languageName(selected)} ($selected)",
            onValueChange = {},
            readOnly = true,
            label = { Text(stringResource(R.string.channel_attr_language)) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { code ->
                DropdownMenuItem(text = { Text("${languageName(code)} ($code)") }, onClick = { onPick(code); open = false })
            }
        }
    }
}
