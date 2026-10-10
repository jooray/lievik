package today.cypherpunk.lievik.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.Event
import today.cypherpunk.lievik.nostr.NostrContent
import today.cypherpunk.lievik.nostr.Segment
import today.cypherpunk.lievik.util.Links

private const val COLLAPSE_AT = 500

/**
 * An event's content with its nostr: references resolved (profiles as @Name
 * links, notes as quote cards, articles as title links), links clickable and
 * images inline. Long content starts collapsed with "Show more", as on the web.
 */
@Composable
fun NostrContentView(event: Event, modifier: Modifier = Modifier, collapsible: Boolean = true) {
    var expanded by rememberSaveable(event.id) { mutableStateOf(false) }
    val long = collapsible && event.content.length > COLLAPSE_AT
    val fallbackNote = stringResource(R.string.nostr_referenced_note)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        event.title?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.titleSmall)
        }
        if (long && !expanded) {
            val preview = remember(event.id, event.content) {
                NostrContent.plainText(event.content, event.references, fallbackNote).take(COLLAPSE_AT).trimEnd() + "…"
            }
            Text(preview, style = MaterialTheme.typography.bodyMedium)
            event.images.firstOrNull()?.let { InlineImage(it) }
        } else {
            val segments = remember(event.id, event.content, event.references, event.images) {
                NostrContent.parse(event.content, event.references, event.images)
            }
            Segments(segments)
        }
        if (long) {
            TextButton(onClick = { expanded = !expanded }, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(if (expanded) R.string.show_less else R.string.show_more))
            }
        }
    }
}

@Composable
private fun Segments(segments: List<Segment>) {
    val link = MaterialTheme.colorScheme.primary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val fallbackNote = stringResource(R.string.nostr_referenced_note)
    val inline = ArrayList<Segment>()

    @Composable
    fun flushInline() {
        if (inline.isEmpty()) return
        val text = buildInline(inline.toList(), link, muted, fallbackNote)
        inline.clear()
        if (text.isNotBlank()) Text(text, style = MaterialTheme.typography.bodyMedium)
    }

    for (segment in segments) {
        when (segment) {
            is Segment.Image -> { flushInline(); InlineImage(segment.url) }
            is Segment.Quote -> { flushInline(); QuoteCard(segment) }
            else -> inline += segment
        }
    }
    flushInline()
}

private fun buildInline(segments: List<Segment>, link: androidx.compose.ui.graphics.Color, muted: androidx.compose.ui.graphics.Color, fallbackNote: String): AnnotatedString =
    buildAnnotatedString {
        val linkStyle = TextLinkStyles(SpanStyle(color = link, textDecoration = TextDecoration.Underline))
        val mentionStyle = TextLinkStyles(SpanStyle(color = link, fontWeight = FontWeight.Medium))
        for (s in segments) when (s) {
            is Segment.Text -> append(s.text)
            is Segment.Link -> withLink(LinkAnnotation.Url(s.url, linkStyle)) { append(s.url) }
            is Segment.Mention -> if (s.url != null) {
                withLink(LinkAnnotation.Url(s.url, mentionStyle)) { append(s.label) }
            } else {
                withStyle(SpanStyle(color = link, fontWeight = FontWeight.Medium)) { append(s.label) }
            }
            is Segment.Article -> if (s.url != null) {
                withLink(LinkAnnotation.Url(s.url, linkStyle)) { append(s.label) }
            } else {
                append(s.label)
            }
            is Segment.Unresolved -> withStyle(SpanStyle(color = muted)) {
                append(if (s.isProfile) NostrContent.shortNpub(s.uri) else fallbackNote)
            }
            else -> {}
        }
    }

@Composable
private fun QuoteCard(quote: Segment.Quote) {
    val context = LocalContext.current
    val unknown = stringResource(R.string.nostr_unknown_author)
    val fallback = stringResource(R.string.nostr_referenced_note)
    Card(
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            .then(if (quote.url != null) Modifier.clickable { Links.openUrl(context, quote.url) } else Modifier),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(8.dp),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(quote.author ?: unknown, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge)
            Text((quote.preview ?: fallback).take(300), style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
fun InlineImage(url: String) {
    val context = LocalContext.current
    AsyncImage(
        model = url,
        contentDescription = stringResource(R.string.image),
        contentScale = ContentScale.FillWidth,
        modifier = Modifier.fillMaxWidth().heightIn(max = 360.dp).clip(RoundedCornerShape(8.dp)).clickable { Links.openUrl(context, url) },
    )
}
