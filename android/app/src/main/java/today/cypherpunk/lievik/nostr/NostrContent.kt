package today.cypherpunk.lievik.nostr

import today.cypherpunk.lievik.data.api.Reference

/** A piece of an event's content, ready to render. */
sealed interface Segment {
    data class Text(val text: String) : Segment
    data class Link(val url: String) : Segment
    data class Image(val url: String) : Segment

    /** nostr:npub / nprofile → "@Name", linking to the profile. */
    data class Mention(val label: String, val url: String?) : Segment

    /** nostr:nevent / note → an inline quote card. */
    data class Quote(val author: String?, val preview: String?, val url: String?) : Segment

    /** nostr:naddr → the article's title or slug, as a link. */
    data class Article(val label: String, val url: String?) : Segment

    /** A nostr: URI the server did not resolve: [isProfile] decides the fallback text. */
    data class Unresolved(val uri: String, val isProfile: Boolean) : Segment
}

/**
 * Turns raw event content into [Segment]s: every `uri` of [references] is
 * replaced by its rendering (docs/API_V1.md "Event.references"), bare URLs
 * become links, image URLs become inline images. Images the event lists but
 * the text never mentions are appended at the end, as the web shows them.
 */
object NostrContent {
    val NOSTR_URI = Regex("""nostr:(?:npub1|nprofile1|nevent1|note1|naddr1)[02-9ac-hj-np-z]+""")
    private val URL = Regex("""https?://[^\s<>"'\])]+""")
    private val IMAGE_EXT = Regex("""\.(?:png|jpe?g|gif|webp|avif)(?:\?\S*)?$""", RegexOption.IGNORE_CASE)
    private val TRAILING_PUNCT = charArrayOf('.', ',', ';', ':', '!', '?')

    fun isImageUrl(url: String, known: Collection<String> = emptyList()) = url in known || IMAGE_EXT.containsMatchIn(url)

    fun parse(content: String, references: List<Reference>, images: List<String> = emptyList()): List<Segment> {
        val byUri = references.associateBy { it.uri }
        val out = ArrayList<Segment>()
        val seenImages = HashSet<String>()
        var cursor = 0
        for (match in NOSTR_URI.findAll(content)) {
            if (match.range.first > cursor) splitUrls(content.substring(cursor, match.range.first), images, seenImages, out)
            out += render(match.value, byUri[match.value])
            cursor = match.range.last + 1
        }
        if (cursor < content.length) splitUrls(content.substring(cursor), images, seenImages, out)
        images.filterNot { it in seenImages }.forEach { out += Segment.Image(it) }
        return merge(out)
    }

    private fun render(uri: String, ref: Reference?): Segment {
        val isProfile = uri.startsWith("nostr:npub") || uri.startsWith("nostr:nprofile")
        if (ref == null) return Segment.Unresolved(uri, isProfile)
        return when (ref.type) {
            "profile" -> Segment.Mention(ref.label?.takeIf { it.isNotBlank() } ?: shortNpub(uri), ref.url)
            "event" -> Segment.Quote(ref.label, ref.preview, ref.url)
            "article" -> Segment.Article(ref.label?.takeIf { it.isNotBlank() } ?: uri.removePrefix("nostr:").take(20), ref.url)
            else -> if (isProfile) Segment.Mention(ref.label ?: shortNpub(uri), ref.url) else Segment.Quote(ref.label, ref.preview, ref.url)
        }
    }

    private fun splitUrls(text: String, images: List<String>, seenImages: MutableSet<String>, out: MutableList<Segment>) {
        var cursor = 0
        for (match in URL.findAll(text)) {
            var url = match.value
            while (url.isNotEmpty() && url.last() in TRAILING_PUNCT) url = url.dropLast(1)
            val end = match.range.first + url.length
            if (match.range.first > cursor) out += Segment.Text(text.substring(cursor, match.range.first))
            if (isImageUrl(url, images)) {
                out += Segment.Image(url)
                seenImages += url
            } else {
                out += Segment.Link(url)
            }
            cursor = end
        }
        if (cursor < text.length) out += Segment.Text(text.substring(cursor))
    }

    /** Adjacent text pieces joined, so the UI builds fewer Text nodes. */
    private fun merge(segments: List<Segment>): List<Segment> {
        val out = ArrayList<Segment>(segments.size)
        for (s in segments) {
            val last = out.lastOrNull()
            if (s is Segment.Text && last is Segment.Text) out[out.size - 1] = Segment.Text(last.text + s.text) else out += s
        }
        return out
    }

    /** "@npub1abcd…wxyz", the web's fallback for an unresolved profile. */
    fun shortNpub(uri: String): String {
        val id = uri.removePrefix("nostr:")
        return if (id.length > 16) "@" + id.take(10) + "…" + id.takeLast(4) else "@$id"
    }

    /**
     * Plain text with references resolved, for previews and copying:
     * profiles as "@Name", notes as "[preview…]" (or [fallbackNote]), articles
     * as their title.
     */
    fun plainText(content: String, references: List<Reference>, fallbackNote: String): String {
        val byUri = references.associateBy { it.uri }
        return NOSTR_URI.replace(content) { m ->
            val ref = byUri[m.value]
            val isProfile = m.value.startsWith("nostr:npub") || m.value.startsWith("nostr:nprofile")
            when {
                ref == null -> if (isProfile) shortNpub(m.value) else fallbackNote
                ref.type == "profile" -> ref.label ?: shortNpub(m.value)
                ref.type == "article" -> ref.label ?: fallbackNote
                else -> ref.preview?.let { "[" + it.take(120) + "]" } ?: fallbackNote
            }
        }
    }
}
