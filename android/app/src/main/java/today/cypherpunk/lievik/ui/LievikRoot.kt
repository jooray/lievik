package today.cypherpunk.lievik.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CurrencyBitcoin
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.ViewStream
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.navigation.NavHostController
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.BuildConfig
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.repo.UiMessage
import today.cypherpunk.lievik.ui.components.BillingDenialDialog
import today.cypherpunk.lievik.ui.components.LocalContainer
import today.cypherpunk.lievik.ui.components.billingEnabled
import today.cypherpunk.lievik.ui.nav.LievikNavHost
import today.cypherpunk.lievik.ui.nav.Routes
import today.cypherpunk.lievik.ui.screens.login.LoginScreen
import today.cypherpunk.lievik.util.Links

/** Deep links handed in by the activity (lievik://billing after a payment). */
object DeepLinks {
    val pending = MutableStateFlow<String?>(null)
}

private data class Tab(val route: String, val label: Int, val icon: ImageVector)

private val TABS = listOf(
    Tab(Routes.DASHBOARD, R.string.nav_dashboard, Icons.Filled.Dashboard),
    Tab(Routes.CHANNELS, R.string.nav_channels, Icons.Filled.Campaign),
    Tab(Routes.EVENTS, R.string.nav_events, Icons.Filled.ViewStream),
    Tab(Routes.ASK, R.string.nav_ask_short, Icons.Filled.Forum),
    Tab(Routes.MORE, R.string.nav_more, Icons.Filled.MoreHoriz),
)

/** What More holds, listed in the side rail directly when the window is tall enough. */
private fun moreTabs(billing: Boolean) = listOfNotNull(
    Tab(Routes.SOURCES, R.string.nav_sources, Icons.Filled.RssFeed),
    Tab(Routes.CHANNELS_AI, R.string.nav_ai_short, Icons.Filled.AutoAwesome),
    Tab(Routes.MANUAL_EVENT, R.string.nav_add_event_short, Icons.AutoMirrored.Filled.NoteAdd),
    Tab(Routes.ACTIVITY, R.string.nav_activity, Icons.Filled.History),
    if (billing) Tab(Routes.BILLING, R.string.nav_billing, Icons.Filled.CurrencyBitcoin) else null,
    Tab(Routes.SETTINGS, R.string.nav_settings, Icons.Filled.Settings),
)

/** A rail item with its label is about 56 dp tall, plus the rail's 4 dp gaps. */
private val RAIL_ITEM_HEIGHT = 64.dp

@Composable
fun LievikRoot() {
    val container = LocalContainer.current
    val signedIn by container.session.signedIn.collectAsState()
    val meta by container.meta.collectAsState()
    val prefs by container.prefs.state.collectAsState()
    val scope = rememberCoroutineScope()

    // Meta on every start/resume: the update gate and the billing switch live there.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        scope.launch {
            container.refreshMeta()
            if (container.session.signedIn.value) {
                container.refreshMe()
                container.sync.sync()
            }
        }
    }

    val android = meta?.android
    if (android != null && android.minVersionCode > BuildConfig.VERSION_CODE) {
        UpdateRequired(android.downloadUrl)
        return
    }

    if (!signedIn) {
        LoginScreen()
        return
    }

    val showUpdate = android != null && android.latestVersionCode > BuildConfig.VERSION_CODE &&
        prefs.dismissedUpdate < android.latestVersionCode
    MainScaffold(
        updateBanner = if (showUpdate) ({
            UpdateBanner(
                downloadUrl = android?.downloadUrl,
                onDismiss = { container.prefs.update { it.copy(dismissedUpdate = android!!.latestVersionCode) } },
            )
        }) else null,
    )
}

@Composable
private fun MainScaffold(updateBanner: (@Composable () -> Unit)?) {
    val container = LocalContainer.current
    val nav = rememberNavController()
    val snackbar = remember { SnackbarHostState() }
    var denial by remember { mutableStateOf<ApiError?>(null) }
    val resources = LocalResources.current
    val windowSize = LocalWindowInfo.current.containerSize
    val windowWidth = with(LocalDensity.current) { windowSize.width.toDp() }
    val windowHeight = with(LocalDensity.current) { windowSize.height.toDp() }
    val wide = windowWidth >= 600.dp
    // A phone has room for five bottom tabs, so More stays. A tablet's rail
    // lists every destination when they fit (a landscape phone's rail does not).
    val billing = billingEnabled()
    val railTabs = remember(billing) { TABS.dropLast(1) + moreTabs(billing) }
    val fullRail = wide && windowHeight >= RAIL_ITEM_HEIGHT * railTabs.size + 96.dp

    LaunchedEffect(Unit) {
        container.messages.flow.collect { message ->
            when (message) {
                is UiMessage.BillingDenial -> denial = message.error
                is UiMessage.Text -> snackbar.showSnackbar(message.text)
                is UiMessage.Res -> snackbar.showSnackbar(resources.getString(message.id, *message.args.toTypedArray()))
                is UiMessage.Plural -> snackbar.showSnackbar(
                    resources.getQuantityString(message.id, message.count, *message.args.toTypedArray()),
                )
            }
        }
    }
    val deepLink by DeepLinks.pending.collectAsState()
    LaunchedEffect(deepLink) {
        val link = deepLink ?: return@LaunchedEffect
        DeepLinks.pending.value = null
        if (link.startsWith("lievik://billing")) nav.navigate(Routes.BILLING) { launchSingleTop = true }
    }

    denial?.let { error ->
        BillingDenialDialog(error, onGoToBilling = { nav.navigate(Routes.BILLING) { launchSingleTop = true } }, onDismiss = { denial = null })
    }

    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val currentTab = if (fullRail) Routes.railItemOf(route) else Routes.tabOf(route)

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            if (!wide) {
                NavigationBar {
                    TABS.forEach { tab ->
                        NavigationBarItem(
                            selected = currentTab == tab.route,
                            onClick = { nav.switchTab(tab.route) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(stringResource(tab.label), maxLines = 1) },
                        )
                    }
                }
            }
        },
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
    ) { padding ->
        Row(Modifier.padding(padding).fillMaxSize()) {
            if (wide) {
                NavigationRail(Modifier.safeDrawingPadding()) {
                    (if (fullRail) railTabs else TABS).forEach { tab ->
                        NavigationRailItem(
                            selected = currentTab == tab.route,
                            onClick = { nav.switchTab(tab.route) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(stringResource(tab.label), maxLines = 2, textAlign = TextAlign.Center) },
                        )
                    }
                }
            }
            Column(Modifier.weight(1f).fillMaxSize().then(if (wide) Modifier.navigationBarsPadding() else Modifier)) {
                LievikNavHost(nav, Modifier.weight(1f))
                updateBanner?.invoke()
            }
        }
    }
}

private fun NavHostController.switchTab(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

@Composable
private fun UpdateBanner(downloadUrl: String?, onDismiss: () -> Unit) {
    val context = LocalContext.current
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.update_available), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            if (downloadUrl != null) TextButton(onClick = { Links.openUrl(context, downloadUrl) }) { Text(stringResource(R.string.update_download)) }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.update_later)) }
        }
    }
}

@Composable
private fun UpdateRequired(downloadUrl: String?) {
    val context = LocalContext.current
    Surface(Modifier.fillMaxSize()) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(32.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(Icons.Filled.SystemUpdate, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.update_required_title), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.update_required_body), textAlign = TextAlign.Center)
            Spacer(Modifier.height(24.dp))
            if (downloadUrl != null) {
                Button(onClick = { Links.openUrl(context, downloadUrl) }) { Text(stringResource(R.string.update_download)) }
            }
        }
    }
}
