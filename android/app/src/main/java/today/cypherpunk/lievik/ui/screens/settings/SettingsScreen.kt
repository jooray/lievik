package today.cypherpunk.lievik.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.BuildConfig
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.UserSettings
import today.cypherpunk.lievik.data.api.UserUpdate
import today.cypherpunk.lievik.data.api.apiCall
import today.cypherpunk.lievik.ui.components.BusyButton
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.LocalContainer
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.SectionCard
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.util.AppLocale
import today.cypherpunk.lievik.util.Times

class SettingsViewModel(private val container: AppContainer) : ViewModel() {
    val saving = MutableStateFlow(false)
    val syncing = container.sync.state

    init {
        viewModelScope.launch { container.refreshMe() }
    }

    fun save(values: Map<String, String?>) {
        saving.value = true
        viewModelScope.launch {
            apiCall { container.api.updateMe(UserUpdate(values)) }
                .onSuccess { r -> r.user?.let { container.setUser(it) }; container.messages.text(r.notice) }
                .onFailure { container.messages.error(it) }
            saving.value = false
        }
    }

    fun setEngine(engine: String) = save(mapOf("rating_engine" to engine))

    fun simple(call: suspend () -> today.cypherpunk.lievik.data.api.Notice) = viewModelScope.launch {
        apiCall { call() }.onSuccess { container.messages.text(it.notice) }.onFailure { container.messages.error(it) }
    }

    fun refreshProfile() = simple { container.api.refreshProfile() }
    fun reindex() = simple { container.api.reindex() }

    fun syncNow() = viewModelScope.launch {
        if (!container.sync.sync()) container.messages.res(R.string.sync_failed)
    }

    fun fullResync() = viewModelScope.launch {
        if (!container.sync.fullResync()) container.messages.res(R.string.sync_failed)
    }

    fun signOut() = viewModelScope.launch { container.signOut() }
}

@Composable
fun SettingsScreen(nav: NavController) {
    val container = LocalContainer.current
    val vm = appViewModel { SettingsViewModel(it) }
    val me by container.me.collectAsState()
    val meta by container.meta.collectAsState()
    val prefs by container.prefs.state.collectAsState()
    val sync by vm.syncing.collectAsState()
    val saving by vm.saving.collectAsState()
    var confirm by remember { mutableStateOf<String?>(null) }

    when (confirm) {
        "signout" -> ConfirmDialog(stringResource(R.string.settings_sign_out_confirm), stringResource(R.string.nav_sign_out), { vm.signOut() }, { confirm = null }, destructive = true)
        "reindex" -> ConfirmDialog(stringResource(R.string.search_index_confirm_rebuild), stringResource(R.string.search_index_rebuild), { vm.reindex() }, { confirm = null })
        "resync" -> ConfirmDialog(stringResource(R.string.sync_full_hint), stringResource(R.string.sync_full), { vm.fullResync() }, { confirm = null })
    }

    ScreenScaffold(title = stringResource(R.string.settings_title), onBack = { nav.popBackStack() }) { modifier ->
        Column(modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // Account
            SectionCard(stringResource(R.string.settings_account)) {
                me?.user?.let { Text(stringResource(R.string.settings_signed_in_as, it.label)); Hint(it.npub) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { vm.refreshProfile() }) { Text(stringResource(R.string.nav_refresh_profile)) }
                    OutlinedButton(onClick = { confirm = "signout" }) { Text(stringResource(R.string.nav_sign_out), color = MaterialTheme.colorScheme.error) }
                }
            }

            // Interface language
            SectionCard(stringResource(R.string.settings_language_label)) {
                val current = AppLocale.current()
                AppLocale.SUPPORTED.forEach { code ->
                    RadioRow(AppLocale.displayName(code), selected = current == code, onClick = { if (current != code) container.changeLanguage(code) })
                }
            }

            val settings = me?.user?.settings ?: UserSettings()

            // Rating engine
            SectionCard(stringResource(R.string.settings_rating_engine_label), subtitle = stringResource(R.string.settings_rating_engine_hint)) {
                val engine = settings.ratingEngine ?: "chat"
                val decisionAvailable = meta?.decisionRatingAvailable == true
                RadioRow(
                    stringResource(R.string.settings_engine_chat_label) + " " + stringResource(R.string.settings_engine_chat_badge),
                    selected = engine != "decision", onClick = { if (engine == "decision") vm.setEngine("chat") },
                )
                Hint(stringResource(R.string.settings_engine_chat_hint), Modifier.padding(start = 48.dp))
                RadioRow(
                    stringResource(R.string.settings_engine_decision_label) + " " + stringResource(R.string.settings_engine_decision_badge),
                    selected = engine == "decision", enabled = decisionAvailable, onClick = { if (engine != "decision") vm.setEngine("decision") },
                )
                Hint(
                    stringResource(if (decisionAvailable) R.string.settings_engine_decision_hint else R.string.settings_engine_unavailable),
                    Modifier.padding(start = 48.dp),
                )
            }

            // AI context + defaults + link templates, saved together like the web form.
            AiAndLinksSection(settings, saving, onSave = vm::save)

            SectionCard(stringResource(R.string.templates_title), subtitle = stringResource(R.string.templates_subtitle)) {
                OutlinedButton(onClick = { nav.navigate(Routes.TEMPLATES) }) { Text(stringResource(R.string.channel_manage_templates)) }
            }
            SectionCard(stringResource(R.string.tokens_title), subtitle = stringResource(R.string.tokens_intro)) {
                OutlinedButton(onClick = { nav.navigate(Routes.TOKENS) }) { Text(stringResource(R.string.tokens_title)) }
            }

            SectionCard(stringResource(R.string.search_index_title), subtitle = stringResource(R.string.search_index_subtitle)) {
                me?.stats?.let { s ->
                    Text(pluralStringResource(R.plurals.search_index_status, s.events, Times.number(s.embedded), Times.number(s.events)))
                }
                OutlinedButton(onClick = { confirm = "reindex" }) { Text(stringResource(R.string.search_index_rebuild)) }
            }

            SectionCard(stringResource(R.string.settings_data)) {
                Text(
                    when {
                        sync.running -> stringResource(R.string.sync_running)
                        prefs.lastSyncAt == 0L -> stringResource(R.string.sync_never)
                        else -> stringResource(R.string.sync_last, Times.relative(java.time.Instant.ofEpochMilli(prefs.lastSyncAt).toString()))
                    },
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { vm.syncNow() }, enabled = !sync.running) { Text(stringResource(R.string.sync_now)) }
                    TextButton(onClick = { confirm = "resync" }, enabled = !sync.running) { Text(stringResource(R.string.sync_full)) }
                }
            }

            SectionCard(stringResource(R.string.settings_about)) {
                Text(stringResource(R.string.settings_app_version, "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"))
                Text(
                    stringResource(R.string.settings_server_build, prefs.serverUrl.removePrefix("https://"), meta?.buildVersion ?: "?"),
                    style = MaterialTheme.typography.bodySmall,
                )
                Hint(stringResource(R.string.billing_self_host))
            }
        }
    }
}

@Composable
private fun AiAndLinksSection(settings: UserSettings, saving: Boolean, onSave: (Map<String, String?>) -> Unit) {
    var systemPrompt by rememberSaveable(settings.systemPrompt) { mutableStateOf(settings.systemPrompt.orEmpty()) }
    var style by rememberSaveable(settings.defaultContentStyle) { mutableStateOf(settings.defaultContentStyle.orEmpty()) }
    var eventLink by rememberSaveable(settings.eventLinkTemplate) { mutableStateOf(settings.eventLinkTemplate.orEmpty()) }
    var naddrLink by rememberSaveable(settings.naddrLinkTemplate) { mutableStateOf(settings.naddrLinkTemplate.orEmpty()) }
    var profileLink by rememberSaveable(settings.profileLinkTemplate) { mutableStateOf(settings.profileLinkTemplate.orEmpty()) }
    val dirty = systemPrompt != settings.systemPrompt.orEmpty() || style != settings.defaultContentStyle.orEmpty() ||
        eventLink != settings.eventLinkTemplate.orEmpty() || naddrLink != settings.naddrLinkTemplate.orEmpty() ||
        profileLink != settings.profileLinkTemplate.orEmpty()

    SectionCard(stringResource(R.string.settings_ai)) {
        Text(stringResource(R.string.settings_system_prompt_label), style = MaterialTheme.typography.titleSmall)
        Hint(stringResource(R.string.settings_system_prompt_intro))
        Hint(stringResource(R.string.settings_system_prompt_make_it_yours))
        OutlinedTextField(
            systemPrompt, { systemPrompt = it },
            textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
            minLines = 6, modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
        )
        OutlinedTextField(
            style, { style = it },
            label = { Text(stringResource(R.string.settings_writing_style_label)) },
            placeholder = { Text(stringResource(R.string.settings_writing_style_placeholder)) },
            supportingText = { Text(stringResource(R.string.settings_writing_style_hint)) },
            minLines = 2, modifier = Modifier.fillMaxWidth(),
        )
    }
    SectionCard(stringResource(R.string.settings_links)) {
        LinkField(eventLink, { eventLink = it }, R.string.settings_event_link_label, R.string.settings_event_link_hint)
        LinkField(naddrLink, { naddrLink = it }, R.string.settings_naddr_link_label, R.string.settings_naddr_link_hint)
        LinkField(profileLink, { profileLink = it }, R.string.settings_profile_link_label, R.string.settings_profile_link_hint)
    }
    BusyButton(
        stringResource(R.string.settings_save),
        onClick = {
            onSave(
                mapOf(
                    "system_prompt" to systemPrompt, "default_content_style" to style,
                    "event_link_template" to eventLink, "naddr_link_template" to naddrLink, "profile_link_template" to profileLink,
                ),
            )
        },
        busy = saving, enabled = dirty, modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun LinkField(value: String, onChange: (String) -> Unit, label: Int, hint: Int) {
    OutlinedTextField(
        value, onChange,
        label = { Text(stringResource(label)) },
        supportingText = { Text(stringResource(hint)) },
        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
fun RadioRow(label: String, selected: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = null, enabled = enabled)
        Text(
            label, modifier = Modifier.padding(start = 12.dp),
            color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
        )
    }
}
