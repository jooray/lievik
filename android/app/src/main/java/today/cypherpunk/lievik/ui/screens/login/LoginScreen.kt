package today.cypherpunk.lievik.ui.screens.login

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.BuildConfig
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiClient
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.ui.components.LocalContainer
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.components.errorText
import today.cypherpunk.lievik.util.Links
import today.cypherpunk.lievik.data.api.LievikSignInBackend
import today.cypherpunk.nostrsignin.AndroidSignerGateway
import today.cypherpunk.nostrsignin.Nip55
import today.cypherpunk.nostrsignin.SignInController
import today.cypherpunk.nostrsignin.SignInFailure
import today.cypherpunk.nostrsignin.SignInMethod
import today.cypherpunk.nostrsignin.SignInState
import today.cypherpunk.nostrsignin.SignInUtil
import today.cypherpunk.nostrsignin.SignerActivityBridge

/**
 * Login through the shared nostr-signin module (android/nostr-signin, vendored
 * from nostr-signin-android): a signer on this phone (NIP-55), nostrconnect://
 * (NIP-46, deep link or QR) or a pasted bunker:// link. The module owns the
 * flow; this screen only renders [SignInState].
 */
class LoginViewModel(private val container: AppContainer) : ViewModel() {
    val gateway = AndroidSignerGateway(container.context)
    val signIn = SignInController(LievikSignInBackend(container), gateway, viewModelScope)

    fun setServer(url: String) {
        container.prefs.update { it.copy(serverUrl = url.trim().trimEnd('/')) }
        viewModelScope.launch { container.refreshMeta() }
    }
}

@Composable
fun LoginScreen() {
    val context = LocalContext.current
    val container = LocalContainer.current
    val vm = appViewModel { LoginViewModel(it) }
    val state by vm.signIn.state.collectAsState()
    val signers = remember { Nip55.signers(context) }
    SignerActivityBridge(vm.gateway)

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 520.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Spacer(Modifier.height(16.dp))
                Text(stringResource(R.string.app_name), style = MaterialTheme.typography.displaySmall, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.login_subtitle), style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.login_no_account), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                HorizontalDivider()

                // NIP-55: a signer installed on this phone.
                Text(stringResource(R.string.login_this_phone_heading), style = MaterialTheme.typography.titleSmall)
                if (signers.isEmpty()) {
                    Text(stringResource(R.string.login_no_signer), style = MaterialTheme.typography.bodySmall)
                    OutlinedButton(onClick = { Links.openUrl(context, "https://github.com/greenart7c3/Amber/releases") }) {
                        Text(stringResource(R.string.login_get_amber))
                    }
                } else {
                    val busy = state == SignInState.Working(SignInMethod.Signer)
                    signers.forEach { app ->
                        Button(
                            onClick = { vm.signIn.signInWithSigner(app.packageName) },
                            enabled = !busy,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                        ) {
                            if (busy) {
                                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                                Spacer(Modifier.size(8.dp))
                            }
                            Text(stringResource(R.string.login_sign_in_with, app.label))
                        }
                    }
                    Text(stringResource(R.string.login_nip55_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    (state as? SignInState.Failed)?.takeIf { it.method == SignInMethod.Signer }?.let { FailureText(it) }
                }
                HorizontalDivider()

                // NIP-46: nostrconnect (deep link into a signer, or QR for another device).
                Text(stringResource(R.string.login_signer_heading), style = MaterialTheme.typography.titleSmall)
                Nip46Section(
                    state.takeIf { it.method() == SignInMethod.NostrConnect } ?: SignInState.Idle,
                    onStart = { vm.signIn.startNostrConnect { uri -> Links.openExternal(context, uri) } },
                )
                HorizontalDivider()

                // bunker:// paste.
                var bunker by rememberSaveable { mutableStateOf("") }
                val bunkerState = state.takeIf { it.method() == SignInMethod.Bunker }
                Text(stringResource(R.string.login_bunker_heading), style = MaterialTheme.typography.titleSmall)
                Text(stringResource(R.string.login_bunker_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(
                    bunker, { bunker = it },
                    label = { Text(stringResource(R.string.login_bunker_label)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedButton(
                    onClick = { vm.signIn.startBunker(bunker) },
                    enabled = bunker.isNotBlank() && bunkerState !is SignInState.Working,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) { Text(stringResource(R.string.login_connect)) }
                when (bunkerState) {
                    is SignInState.Working, is SignInState.Waiting -> Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.size(12.dp))
                        Text(stringResource(R.string.login_waiting))
                    }
                    is SignInState.Expired -> Text(stringResource(R.string.login_expired))
                    is SignInState.Failed -> FailureText(bunkerState)
                    else -> {}
                }
                HorizontalDivider()

                ServerSection(container.prefs.current.serverUrl, onSave = vm::setServer)
                Text("v${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private fun SignInState.method(): SignInMethod? = when (this) {
    is SignInState.Working -> method
    is SignInState.Waiting -> method
    is SignInState.Expired -> method
    is SignInState.Failed -> method
    else -> null
}

@Composable
private fun ErrorLine(text: String) {
    if (text.isNotBlank()) Text(text, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
}

@Composable
private fun FailureText(failed: SignInState.Failed) {
    val error = failed.cause as? ApiError
    when {
        failed.failure == SignInFailure.SignerRejected -> ErrorLine(stringResource(R.string.login_signer_rejected))
        failed.failure == SignInFailure.SignerEmpty -> ErrorLine(stringResource(R.string.login_signer_cancelled))
        failed.failure == SignInFailure.SignerMissing -> ErrorLine(stringResource(R.string.login_no_signer))
        failed.failure == SignInFailure.InvalidBunkerLink -> ErrorLine(stringResource(R.string.login_bunker_invalid))
        failed.method == SignInMethod.Bunker && error is ApiError.Validation -> ErrorLine(stringResource(R.string.login_bunker_invalid))
        error is ApiError.Unauthorized -> ErrorLine(stringResource(R.string.login_failed))
        error is ApiError.Refused && error.code == "busy" -> {
            Text(stringResource(R.string.login_busy_title), style = MaterialTheme.typography.titleSmall)
            Text(stringResource(R.string.login_busy_message))
        }
        error is ApiError.RateLimited -> {
            Text(stringResource(R.string.login_rate_limited_title), style = MaterialTheme.typography.titleSmall)
            Text(stringResource(R.string.login_rate_limited_message))
        }
        error != null -> ErrorLine(errorText(error))
        else -> ErrorLine(stringResource(R.string.login_failed))
    }
}

@Composable
private fun Nip46Section(state: SignInState, onStart: () -> Unit) {
    val context = LocalContext.current
    // No signer on this phone: create the code and show its QR at once, for a
    // signer on another device. There is nothing to tap through to.
    val noSigner = remember { !SignInUtil.canOpen(context, "nostrconnect://") }
    var showQr by rememberSaveable { mutableStateOf(noSigner) }
    var autoStarted by rememberSaveable { mutableStateOf(false) }
    if (noSigner && state == SignInState.Idle && !autoStarted) {
        LaunchedEffect(Unit) { autoStarted = true; onStart() }
    }
    when (state) {
        is SignInState.Waiting -> {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.size(12.dp))
                Text(stringResource(R.string.login_waiting))
            }
            state.authUrl?.let { url ->
                Text(stringResource(R.string.login_auth_challenge), style = MaterialTheme.typography.bodySmall)
                Button(onClick = { Links.openUrl(context, url) }) { Text(stringResource(R.string.login_open_approval)) }
            }
            state.uri?.let { uri ->
                if (SignInUtil.canOpen(context, uri)) {
                    Button(onClick = { Links.openExternal(context, uri) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                        Text(stringResource(R.string.login_open_in_signer))
                    }
                }
                TextButton(onClick = { showQr = !showQr }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(stringResource(if (showQr) R.string.login_hide_qr else R.string.login_scan_hint))
                    Icon(if (showQr) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null)
                }
                if (showQr) {
                    val bitmap = remember(uri) { SignInUtil.qrBitmap(uri).asImageBitmap() }
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                        Image(
                            bitmap, contentDescription = stringResource(R.string.login_qr_description),
                            modifier = Modifier.size(260.dp).background(Color.White).padding(8.dp),
                        )
                    }
                    TextButton(onClick = { Links.copy(context, "nostrconnect", uri) }) { Text(stringResource(R.string.common_copy)) }
                }
            }
            Text(stringResource(R.string.login_stale_notice), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = onStart) { Text(stringResource(R.string.login_new_code)) }
        }
        is SignInState.Expired -> {
            Text(stringResource(R.string.login_expired))
            Button(onClick = onStart) { Text(stringResource(R.string.login_new_code)) }
        }
        is SignInState.Failed -> {
            FailureText(state)
            Button(onClick = onStart) { Text(stringResource(R.string.login_try_again)) }
        }
        else -> {
            val starting = state is SignInState.Working
            OutlinedButton(onClick = onStart, enabled = !starting, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                if (starting) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.size(8.dp))
                }
                Text(stringResource(R.string.login_open_in_signer))
            }
            Text(stringResource(R.string.login_signer_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ServerSection(current: String, onSave: (String) -> Unit) {
    var open by rememberSaveable { mutableStateOf(current != BuildConfig.DEFAULT_SERVER) }
    var server by rememberSaveable { mutableStateOf(current) }
    TextButton(onClick = { open = !open }, modifier = Modifier.heightIn(min = 48.dp)) {
        Text(stringResource(R.string.login_advanced))
        Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null)
    }
    if (open) {
        Text(stringResource(R.string.login_server_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        val valid = ApiClient.apiBase(server) != null && (server.startsWith("https://") || server.startsWith("http://"))
        OutlinedTextField(
            server, { server = it },
            label = { Text(stringResource(R.string.login_server_label)) },
            singleLine = true,
            isError = !valid,
            supportingText = {
                when {
                    !valid -> Text(stringResource(R.string.login_server_invalid))
                    server.startsWith("http://") -> Text(stringResource(R.string.login_server_insecure))
                }
            },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth(),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { onSave(server) }, enabled = valid && server.trimEnd('/') != current) { Text(stringResource(R.string.common_save)) }
            TextButton(onClick = { server = BuildConfig.DEFAULT_SERVER; onSave(BuildConfig.DEFAULT_SERVER) }) {
                Text(stringResource(R.string.login_server_reset))
            }
        }
    }
}
