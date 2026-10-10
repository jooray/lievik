package today.cypherpunk.lievik.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.Event
import today.cypherpunk.lievik.util.Times

@Composable
fun eventTypeLabel(type: String?): String? = when (type) {
    "original" -> stringResource(R.string.event_type_original)
    "reply" -> stringResource(R.string.event_type_reply)
    "repost" -> stringResource(R.string.event_type_repost)
    "long_form" -> stringResource(R.string.event_type_long_form)
    else -> null
}

@Composable
fun sourceLabel(name: String?, type: String?): String = when {
    type == "manual" -> stringResource(R.string.source_label_manual)
    !name.isNullOrBlank() -> name
    type == null -> stringResource(R.string.source_label_unknown)
    else -> stringResource(R.string.source_label_unnamed)
}

/**
 * One event in a list. In selection mode a tap toggles the checkbox; otherwise
 * a tap opens it and a long press starts selecting.
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
fun EventCard(
    event: Event,
    modifier: Modifier = Modifier,
    score: Int? = null,
    reason: String? = null,
    used: Boolean = false,
    showTopChannels: Boolean = false,
    selecting: Boolean = false,
    selected: Boolean = false,
    onToggle: (() -> Unit)? = null,
    onOpen: () -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth().alpha(if (used && !selected) 0.6f else 1f).combinedClickable(
            onClick = { if (selecting && onToggle != null) onToggle() else onOpen() },
            onLongClick = onToggle,
        ),
        colors = CardDefaults.cardColors(
            containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(1.dp),
    ) {
        Row(Modifier.padding(12.dp)) {
            if (selecting && onToggle != null) {
                Checkbox(checked = selected, onCheckedChange = { onToggle() })
                Spacer(Modifier.width(4.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Avatar(event.author?.pictureUrl, size = 32.dp)
                    Column(Modifier.weight(1f)) {
                        Text(
                            event.author?.name ?: sourceLabel(event.sourceName, event.sourceType),
                            style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                        val meta = listOfNotNull(
                            stringResource(R.string.channel_from_source, sourceLabel(event.sourceName, event.sourceType)),
                            Times.relative(event.publishedAt).takeIf { it.isNotEmpty() },
                        ).joinToString(" · ")
                        Text(meta, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    RelevanceChip(score)
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    eventTypeLabel(event.eventType)?.takeIf { event.eventType != "original" }?.let { Tag(it) }
                    if (used) Tag(stringResource(R.string.channel_used))
                    if (showTopChannels) event.topChannels.take(3).forEach { top ->
                        Tag(listOfNotNull(top.channelName, top.relevanceScore?.let { stringResource(R.string.percent, it) }).joinToString(" "))
                    }
                }
                if (!reason.isNullOrBlank()) {
                    Text(reason.take(150), style = MaterialTheme.typography.bodySmall, fontStyle = FontStyle.Italic, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                NostrContentView(event)
            }
        }
    }
}
