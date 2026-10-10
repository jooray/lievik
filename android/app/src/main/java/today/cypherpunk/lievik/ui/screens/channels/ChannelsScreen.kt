package today.cypherpunk.lievik.ui.screens.channels

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import today.cypherpunk.lievik.AppContainer
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.Channel
import today.cypherpunk.lievik.ui.components.EmptyState
import today.cypherpunk.lievik.ui.components.Hint
import today.cypherpunk.lievik.ui.components.LoadingBox
import today.cypherpunk.lievik.ui.components.ScreenScaffold
import today.cypherpunk.lievik.ui.components.Tag
import today.cypherpunk.lievik.ui.components.appViewModel
import today.cypherpunk.lievik.ui.nav.Routes

class ChannelsViewModel(private val container: AppContainer) : ViewModel() {
    val channels = container.dao.channels().map { rows -> rows.map { it.toModel() } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)
    val refreshing = MutableStateFlow(false)

    fun sync() = viewModelScope.launch {
        refreshing.value = true
        container.sync.sync()
        refreshing.value = false
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelsScreen(nav: NavController) {
    val vm = appViewModel { ChannelsViewModel(it) }
    val channels by vm.channels.collectAsState()
    val refreshing by vm.refreshing.collectAsState()
    ScreenScaffold(
        title = stringResource(R.string.channels_title),
        actions = {
            IconButton(onClick = { nav.navigate(Routes.CHANNELS_AI) }) {
                Icon(Icons.Filled.AutoAwesome, contentDescription = stringResource(R.string.channels_create_with_ai))
            }
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { nav.navigate(Routes.CHANNEL_NEW) },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text(stringResource(R.string.channels_create_channel)) },
            )
        },
    ) { modifier ->
        PullToRefreshBox(refreshing, onRefresh = { vm.sync() }, modifier = modifier) {
            val list = channels
            when {
                list == null -> LoadingBox()
                list.isEmpty() -> EmptyState(stringResource(R.string.channels_empty_title), stringResource(R.string.channels_empty_body)) {
                    Button(onClick = { nav.navigate(Routes.CHANNEL_NEW) }) { Text(stringResource(R.string.channels_create_channel)) }
                    OutlinedButton(onClick = { nav.navigate(Routes.CHANNELS_AI) }) { Text(stringResource(R.string.channels_create_with_ai)) }
                }
                else -> LazyColumn(contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    item { Hint(stringResource(R.string.channels_subtitle)) }
                    items(list, key = { it.id }) { channel -> ChannelRow(channel) { nav.navigate(Routes.channel(channel.id)) } }
                }
            }
        }
    }
}

@Composable
private fun ChannelRow(channel: Channel, onOpen: () -> Unit) {
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(1.dp),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(channel.name, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                channel.language?.let { Tag(it.uppercase()) }
            }
            channel.description?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (channel.pendingCount > 0) {
                    Badge(containerColor = MaterialTheme.colorScheme.primary) {
                        Text(pluralStringResource(R.plurals.channels_pending, channel.pendingCount, channel.pendingCount), modifier = Modifier.padding(horizontal = 4.dp))
                    }
                }
                Tag(stringResource(R.string.channel_threshold, channel.settings.relevanceThreshold.toString()))
            }
        }
    }
}
