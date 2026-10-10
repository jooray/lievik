package today.cypherpunk.lievik.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.ApiToken
import today.cypherpunk.lievik.data.api.ContentTemplate
import today.cypherpunk.lievik.data.api.NameBody
import today.cypherpunk.lievik.data.api.TemplateBody
import today.cypherpunk.lievik.data.api.TemplatesResponse
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.ui.components.BusyButton
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.ErrorState
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.util.Links
import today.cypherpunk.lievik.util.Times

// ---------------------------------------------------------------- content templates

class TemplatesViewModel(private val container: AppContainer) : ViewModel() {
    val data = MutableStateFlow<TemplatesResponse?>(null)
    val error = MutableStateFlow<ApiError?>(null)
    val saving = MutableStateFlow(false)

    init { load() }

    fun load() = viewModelScope.launch {
        apiCall { container.api.templates() }
            .onSuccess { data.value = it; error.value = null }
            .onFailure { error.value = it as ApiError }
    }

    fun create(name: String, template: String, then: () -> Unit = {}) = mutate({ container.api.createTemplate(TemplateBody(name.trim(), template)) }, then)

    fun update(index: Int, name: String, template: String, then: () -> Unit = {}) =
        mutate({ container.api.updateTemplate(index, TemplateBody(name.trim(), template)) }, then)

    fun delete(index: Int) = mutate({ container.api.deleteTemplate(index) })

    private fun mutate(call: suspend () -> today.cypherpunk.lievik.data.api.Notice, then: () -> Unit = {}) {
        saving.value = true
        viewModelScope.launch {
            apiCall { call() }
                .onSuccess { container.messages.text(it.notice); then(); load() }
                .onFailure { container.messages.error(it) }
            saving.value = false
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TemplatesScreen(onBack: () -> Unit) {
    val vm = appViewModel { TemplatesViewModel(it) }
    val data by vm.data.collectAsState()
    val error by vm.error.collectAsState()
    val saving by vm.saving.collectAsState()
    var editing by remember { mutableStateOf<ContentTemplate?>(null) }
    var deleting by remember { mutableStateOf<ContentTemplate?>(null) }

    deleting?.let { t ->
        ConfirmDialog(stringResource(R.string.templates_confirm_delete), stringResource(R.string.common_delete), { vm.delete(t.index) }, { deleting = null }, destructive = true)
    }
    editing?.let { t ->
        TemplateDialog(t, saving, onDismiss = { editing = null }, onSave = { name, body ->
            if (t.index >= 0) vm.update(t.index, name, body) { editing = null } else vm.create(name, body) { editing = null }
        })
    }

    ScreenScaffold(title = stringResource(R.string.templates_title), onBack = onBack) { modifier ->
        val d = data
        when {
            d == null && error != null -> ErrorState(error!!, onRetry = { vm.load() }, modifier = modifier)
            d == null -> LoadingBox(modifier)
            else -> LazyColumn(modifier, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item { Hint(stringResource(R.string.templates_subtitle)) }
                if (d.defaults.isNotEmpty()) item {
                    SectionCard(stringResource(R.string.templates_add_from_preset)) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            d.defaults.forEach { preset ->
                                AssistChip(onClick = { vm.create(preset.name, preset.template) }, label = { Text(preset.name) })
                            }
                        }
                    }
                }
                if (d.templates.isEmpty()) item { EmptyState(stringResource(R.string.templates_empty)) }
                items(d.templates, key = { it.index }) { t ->
                    SectionCard(t.name) {
                        Text(t.template.take(400), style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, maxLines = 8)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = { editing = t }) { Text(stringResource(R.string.common_edit)) }
                            TextButton(onClick = { deleting = t }) { Text(stringResource(R.string.common_delete), color = MaterialTheme.colorScheme.error) }
                        }
                    }
                }
                item {
                    Button(onClick = { editing = ContentTemplate(-1, "", "") }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.templates_add_custom))
                    }
                }
            }
        }
    }
}

@Composable
private fun TemplateDialog(template: ContentTemplate, saving: Boolean, onDismiss: () -> Unit, onSave: (String, String) -> Unit) {
    var name by rememberSaveable { mutableStateOf(template.name) }
    var body by rememberSaveable { mutableStateOf(template.template) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(if (template.index >= 0) R.string.common_edit else R.string.templates_add_custom)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    name, { name = it }, label = { Text(stringResource(R.string.templates_name)) },
                    placeholder = { Text(stringResource(R.string.templates_name_placeholder)) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    body, { body = it }, label = { Text(stringResource(R.string.templates_content)) },
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    minLines = 6, maxLines = 14, modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(name, body) }, enabled = !saving && name.isNotBlank() && body.isNotBlank()) {
                Text(stringResource(if (template.index >= 0) R.string.templates_save else R.string.templates_add))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
    )
}

// ---------------------------------------------------------------- API tokens

class ApiTokensViewModel(private val container: AppContainer) : ViewModel() {
    val tokens = MutableStateFlow<List<ApiToken>?>(null)
    val error = MutableStateFlow<ApiError?>(null)
    val created = MutableStateFlow<Pair<String, String>?>(null)
    val saving = MutableStateFlow(false)

    init { load() }

    fun load() = viewModelScope.launch {
        apiCall { container.api.apiTokens() }
            .onSuccess { tokens.value = it.apiTokens; error.value = null }
            .onFailure { error.value = it as ApiError }
    }

    fun create(name: String) {
        if (name.isBlank()) {
            container.messages.res(R.string.tokens_name_required)
            return
        }
        saving.value = true
        viewModelScope.launch {
            apiCall { container.api.createApiToken(NameBody(name.trim())) }
                .onSuccess { created.value = name.trim() to it.plainToken; load() }
                .onFailure { container.messages.error(it) }
            saving.value = false
        }
    }

    fun revoke(id: Long) = viewModelScope.launch {
        apiCall { container.api.revokeApiToken(id) }
            .onSuccess { if (it.notice != null) container.messages.text(it.notice) else container.messages.res(R.string.token_revoked); load() }
            .onFailure { container.messages.error(it) }
    }

    fun dismissCreated() {
        created.value = null
    }
}

@Composable
fun ApiTokensScreen(onBack: () -> Unit) {
    val vm = appViewModel { ApiTokensViewModel(it) }
    val tokens by vm.tokens.collectAsState()
    val error by vm.error.collectAsState()
    val created by vm.created.collectAsState()
    val saving by vm.saving.collectAsState()
    val context = LocalContext.current
    var name by rememberSaveable { mutableStateOf("") }
    var revoking by remember { mutableStateOf<ApiToken?>(null) }

    revoking?.let { t ->
        ConfirmDialog(stringResource(R.string.tokens_confirm_revoke), stringResource(R.string.tokens_revoke), { vm.revoke(t.id) }, { revoking = null }, destructive = true)
    }

    ScreenScaffold(title = stringResource(R.string.tokens_title), onBack = onBack) { modifier ->
        LazyColumn(modifier, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { Hint(stringResource(R.string.tokens_intro)) }
            created?.let { (tokenName, plain) ->
                item {
                    SectionCard(stringResource(R.string.tokens_new_token_label)) {
                        Text(stringResource(R.string.tokens_created, tokenName), style = MaterialTheme.typography.bodyMedium)
                        SelectionContainer { Text(plain, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { Links.copy(context, "token", plain) }) {
                                Icon(Icons.Filled.ContentCopy, contentDescription = null)
                                Text(stringResource(R.string.common_copy))
                            }
                            TextButton(onClick = { vm.dismissCreated() }) { Text(stringResource(R.string.done)) }
                        }
                    }
                }
            }
            item {
                SectionCard {
                    OutlinedTextField(
                        name, { name = it }, label = { Text(stringResource(R.string.tokens_name_label)) },
                        placeholder = { Text(stringResource(R.string.tokens_name_placeholder)) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                    BusyButton(stringResource(R.string.tokens_generate), onClick = { vm.create(name); name = "" }, busy = saving, enabled = name.isNotBlank())
                }
            }
            val list = tokens
            when {
                list == null && error != null -> item { ErrorState(error!!, onRetry = { vm.load() }) }
                list == null -> item { LoadingBox() }
                list.isEmpty() -> item { EmptyState(stringResource(R.string.tokens_empty)) }
                else -> items(list, key = { it.id }) { t ->
                    SectionCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(t.name, style = MaterialTheme.typography.titleSmall)
                                t.preview?.let { Text(it, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
                                Hint(stringResource(R.string.tokens_created_column) + ": " + Times.date(t.createdAt))
                                Hint(
                                    stringResource(R.string.tokens_last_used) + ": " +
                                        (t.lastUsedAt?.let { Times.relative(it) } ?: stringResource(R.string.tokens_never)),
                                )
                                if (t.current) Tag(stringResource(R.string.token_this_device))
                            }
                            if (!t.current) {
                                IconButton(onClick = { revoking = t }, modifier = Modifier.heightIn(min = 48.dp)) {
                                    Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.tokens_revoke))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
