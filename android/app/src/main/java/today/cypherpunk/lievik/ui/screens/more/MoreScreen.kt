package today.cypherpunk.lievik.ui.screens.more

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CurrencyBitcoin
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.foundation.clickable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.ui.components.Avatar
import today.cypherpunk.lievik.ui.components.BillingBanner
import today.cypherpunk.lievik.ui.components.ConfirmDialog
import today.cypherpunk.lievik.ui.components.LocalContainer
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.billingEnabled
import today.cypherpunk.lievik.ui.nav.Routes

@Composable
fun MoreScreen(nav: NavController) {
    val container = LocalContainer.current
    val me by container.me.collectAsState()
    val scope = rememberCoroutineScope()
    var confirmSignOut by remember { mutableStateOf(false) }
    if (confirmSignOut) {
        ConfirmDialog(stringResource(R.string.settings_sign_out_confirm), stringResource(R.string.nav_sign_out), onConfirm = {
            scope.launch { container.signOut() }
        }, onDismiss = { confirmSignOut = false }, destructive = true)
    }
    ScreenScaffold(title = stringResource(R.string.nav_more)) { modifier ->
        Column(modifier.verticalScroll(rememberScrollState())) {
            me?.user?.let { user ->
                ListItem(
                    headlineContent = { Text(user.label) },
                    supportingContent = { Text(user.npub.take(24) + "…") },
                    leadingContent = { Avatar(user.pictureUrl, size = 44.dp) },
                )
            }
            BillingBanner(onOpenBilling = { nav.navigate(Routes.BILLING) }, modifier = Modifier.padding(horizontal = 16.dp))
            HorizontalDivider()
            Entry(Icons.Filled.RssFeed, stringResource(R.string.nav_sources)) { nav.navigate(Routes.SOURCES) }
            Entry(Icons.Filled.AutoAwesome, stringResource(R.string.ai_title)) { nav.navigate(Routes.CHANNELS_AI) }
            Entry(Icons.AutoMirrored.Filled.NoteAdd, stringResource(R.string.nav_add_event)) { nav.navigate(Routes.MANUAL_EVENT) }
            Entry(Icons.Filled.History, stringResource(R.string.nav_activity)) { nav.navigate(Routes.ACTIVITY) }
            if (billingEnabled()) Entry(Icons.Filled.CurrencyBitcoin, stringResource(R.string.nav_billing)) { nav.navigate(Routes.BILLING) }
            Entry(Icons.Filled.Settings, stringResource(R.string.nav_settings)) { nav.navigate(Routes.SETTINGS) }
            HorizontalDivider()
            Entry(Icons.AutoMirrored.Filled.Logout, stringResource(R.string.nav_sign_out)) { confirmSignOut = true }
        }
    }
}

@Composable
private fun Entry(icon: ImageVector, label: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(label) },
        leadingContent = { Icon(icon, contentDescription = null) },
        modifier = Modifier.clickable(onClick = onClick),
    )
}
