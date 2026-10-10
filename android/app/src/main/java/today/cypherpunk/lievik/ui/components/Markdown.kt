package today.cypherpunk.lievik.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em

/** Markdown blocks: the subset the AI writes (headings, lists, quotes, code, rules). */
sealed interface MdBlock {
    data class Heading(val level: Int, val text: String) : MdBlock
    data class Paragraph(val text: String) : MdBlock
    data class ListBlock(val items: List<String>, val ordered: Boolean, val start: Int = 1) : MdBlock
    data class Quote(val text: String) : MdBlock
    data class Code(val text: String) : MdBlock
    data object Rule : MdBlock
}

/** Inline spans, independent of Compose so they can be unit-tested. */
sealed interface MdInline {
    data class Plain(val text: String) : MdInline
    data class Bold(val children: List<MdInline>) : MdInline
    data class Italic(val children: List<MdInline>) : MdInline
    data class Strike(val children: List<MdInline>) : MdInline
    data class Code(val text: String) : MdInline
    data class Link(val children: List<MdInline>, val url: String) : MdInline
    /** An "Ask your content" citation, `[EVENT:123]`. */
    data class Citation(val eventId: Long) : MdInline
}

object MarkdownParser {
    private val HEADING = Regex("""^(#{1,6})\s+(.*?)\s*#*\s*$""")
    private val BULLET = Regex("""^\s{0,3}[-*+]\s+(.*)$""")
    private val ORDERED = Regex("""^\s{0,3}(\d{1,9})[.)]\s+(.*)$""")
    private val RULE = Regex("""^\s{0,3}([-*_])(\s*\1){2,}\s*$""")
    private val CITATION = Regex("""\[EVENT:(\d+)]""")
    private val AUTOLINK = Regex("""https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]""")

    fun blocks(markdown: String): List<MdBlock> {
        val lines = markdown.replace("\r\n", "\n").split("\n")
        val out = ArrayList<MdBlock>()
        val paragraph = StringBuilder()
        fun flush() {
            if (paragraph.isNotBlank()) out += MdBlock.Paragraph(paragraph.toString().trim())
            paragraph.clear()
        }
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            val trimmed = line.trim()
            when {
                trimmed.startsWith("```") || trimmed.startsWith("~~~") -> {
                    flush()
                    val fence = trimmed.take(3)
                    val code = StringBuilder()
                    i++
                    while (i < lines.size && !lines[i].trim().startsWith(fence)) {
                        if (code.isNotEmpty()) code.append('\n')
                        code.append(lines[i])
                        i++
                    }
                    out += MdBlock.Code(code.toString())
                }
                trimmed.isEmpty() -> flush()
                RULE.matches(line) -> { flush(); out += MdBlock.Rule }
                HEADING.matches(trimmed) -> {
                    flush()
                    val m = HEADING.find(trimmed)!!
                    out += MdBlock.Heading(m.groupValues[1].length, m.groupValues[2])
                }
                trimmed.startsWith(">") -> {
                    flush()
                    val quote = StringBuilder()
                    while (i < lines.size && lines[i].trim().startsWith(">")) {
                        if (quote.isNotEmpty()) quote.append('\n')
                        quote.append(lines[i].trim().removePrefix(">").trimStart())
                        i++
                    }
                    out += MdBlock.Quote(quote.toString())
                    continue
                }
                BULLET.matches(line) || ORDERED.matches(line) -> {
                    flush()
                    val ordered = ORDERED.matches(line)
                    val start = if (ordered) ORDERED.find(line)!!.groupValues[1].toIntOrNull() ?: 1 else 1
                    val items = ArrayList<String>()
                    while (i < lines.size) {
                        val l = lines[i]
                        val m = (if (ordered) ORDERED else BULLET).find(l)
                        when {
                            m != null && (if (ordered) ORDERED.matches(l) else BULLET.matches(l)) ->
                                items += m.groupValues.last()
                            l.isNotBlank() && l.startsWith("  ") && items.isNotEmpty() ->
                                items[items.size - 1] = items.last() + " " + l.trim()
                            else -> break
                        }
                        i++
                    }
                    out += MdBlock.ListBlock(items, ordered, start)
                    continue
                }
                else -> {
                    if (paragraph.isNotEmpty()) paragraph.append('\n')
                    paragraph.append(line.trimEnd())
                }
            }
            i++
        }
        flush()
        return out
    }

    fun inline(text: String): List<MdInline> = Inline(text).parse(0, null).first

    private class Inline(val s: String) {
        /** Parses from [start] until [closer] (or the end); returns spans and the index after the closer. */
        fun parse(start: Int, closer: String?): Pair<List<MdInline>, Int> {
            val out = ArrayList<MdInline>()
            val plain = StringBuilder()
            fun flush() {
                if (plain.isNotEmpty()) out += MdInline.Plain(plain.toString())
                plain.clear()
            }
            var i = start
            while (i < s.length) {
                if (closer != null && s.startsWith(closer, i) && (plain.isNotEmpty() || out.isNotEmpty())) {
                    flush()
                    return out to i + closer.length
                }
                val c = s[i]
                when {
                    c == '\\' && i + 1 < s.length && s[i + 1] in "\\`*_[]()#+-.!~>" -> { plain.append(s[i + 1]); i += 2; continue }
                    c == '`' -> {
                        val end = s.indexOf('`', i + 1)
                        if (end > i) { flush(); out += MdInline.Code(s.substring(i + 1, end)); i = end + 1; continue }
                    }
                    s.startsWith("**", i) || s.startsWith("__", i) -> {
                        val marker = s.substring(i, i + 2)
                        if (s.indexOf(marker, i + 2) > i + 2 && (marker == "**" || boundaryBefore(i))) {
                            val (children, next) = parse(i + 2, marker)
                            if (next <= s.length && s.startsWith(marker, next - 2)) {
                                flush(); out += MdInline.Bold(children); i = next; continue
                            }
                        }
                    }
                    s.startsWith("~~", i) -> {
                        if (s.indexOf("~~", i + 2) > i + 2) {
                            val (children, next) = parse(i + 2, "~~")
                            flush(); out += MdInline.Strike(children); i = next; continue
                        }
                    }
                    (c == '*' || c == '_') && i + 1 < s.length && !s[i + 1].isWhitespace() && (c == '*' || boundaryBefore(i)) -> {
                        val end = findCloser(c, i + 1)
                        if (end > 0) {
                            val (children, _) = Inline(s.substring(i + 1, end)).parse(0, null)
                            flush(); out += MdInline.Italic(children); i = end + 1; continue
                        }
                    }
                    c == '[' && s.startsWith("[EVENT:", i) -> {
                        val m = CITATION.matchAt(s, i)
                        val id = m?.groupValues?.get(1)?.toLongOrNull()
                        if (m != null && id != null) { flush(); out += MdInline.Citation(id); i = m.range.last + 1; continue }
                    }
                    c == '[' -> {
                        val close = s.indexOf(']', i + 1)
                        if (close > i && close + 1 < s.length && s[close + 1] == '(') {
                            val paren = s.indexOf(')', close + 2)
                            if (paren > close) {
                                val url = s.substring(close + 2, paren).trim().substringBefore(' ')
                                val (children, _) = Inline(s.substring(i + 1, close)).parse(0, null)
                                flush(); out += MdInline.Link(children, url); i = paren + 1; continue
                            }
                        }
                    }
                    c == 'h' && (s.startsWith("http://", i) || s.startsWith("https://", i)) -> {
                        val m = AUTOLINK.find(s, i)
                        if (m != null && m.range.first == i) {
                            flush(); out += MdInline.Link(listOf(MdInline.Plain(m.value)), m.value); i = m.range.last + 1; continue
                        }
                    }
                }
                plain.append(c)
                i++
            }
            flush()
            return out to s.length
        }

        private fun boundaryBefore(i: Int) = i == 0 || !s[i - 1].isLetterOrDigit()

        private fun findCloser(c: Char, from: Int): Int {
            var j = from
            while (j < s.length) {
                if (s[j] == c && !s[j - 1].isWhitespace() && (c == '*' || j + 1 == s.length || !s[j + 1].isLetterOrDigit())) {
                    if (c == '*' && j + 1 < s.length && s[j + 1] == '*') { j += 2; continue }
                    return j
                }
                j++
            }
            return -1
        }
    }
}

/** Colours of a citation badge; [onClick] opens the cited event (no badge link without it). */
class CitationStyle(val text: Color, val background: Color, val onClick: ((Long) -> Unit)?)

fun AnnotatedString.Builder.appendInline(spans: List<MdInline>, linkColor: Color, codeBackground: Color, citation: CitationStyle? = null) {
    for (span in spans) when (span) {
        is MdInline.Plain -> append(span.text)
        is MdInline.Bold -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { appendInline(span.children, linkColor, codeBackground, citation) }
        is MdInline.Italic -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { appendInline(span.children, linkColor, codeBackground, citation) }
        is MdInline.Strike -> withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { appendInline(span.children, linkColor, codeBackground, citation) }
        is MdInline.Code -> withStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = codeBackground)) { append(span.text) }
        is MdInline.Link -> withLink(
            LinkAnnotation.Url(span.url, TextLinkStyles(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline))),
        ) { appendInline(span.children, linkColor, codeBackground, citation) }
        is MdInline.Citation -> {
            val style = SpanStyle(
                color = citation?.text ?: linkColor,
                background = citation?.background ?: Color.Unspecified,
                fontWeight = FontWeight.Medium,
                fontSize = 0.85.em,
            )
            val label = "\u00A0${span.eventId}\u00A0"
            val onClick = citation?.onClick
            if (onClick != null) {
                withLink(LinkAnnotation.Clickable("event:${span.eventId}", TextLinkStyles(style)) { onClick(span.eventId) }) { append(label) }
            } else {
                withStyle(style) { append(label) }
            }
        }
    }
}

/**
 * Renders generated content and chat answers. Text is selectable; links open in the browser;
 * `[EVENT:id]` citations become badges that call [onCitation].
 */
@Composable
fun MarkdownText(markdown: String, modifier: Modifier = Modifier, onCitation: ((Long) -> Unit)? = null) {
    val blocks = remember(markdown) { MarkdownParser.blocks(markdown) }
    val link = MaterialTheme.colorScheme.primary
    val codeBg = MaterialTheme.colorScheme.surfaceVariant
    val citation = CitationStyle(MaterialTheme.colorScheme.onTertiaryContainer, MaterialTheme.colorScheme.tertiaryContainer, onCitation)
    val typography = MaterialTheme.typography
    fun inline(text: String) = buildAnnotatedString { appendInline(MarkdownParser.inline(text), link, codeBg, citation) }
    SelectionContainer(modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (block in blocks) when (block) {
                is MdBlock.Heading -> Text(
                    inline(block.text),
                    style = when (block.level) {
                        1 -> typography.headlineSmall
                        2 -> typography.titleLarge
                        3 -> typography.titleMedium
                        else -> typography.titleSmall
                    },
                )
                is MdBlock.Paragraph -> Text(inline(block.text), style = typography.bodyMedium)
                is MdBlock.Quote -> Row(Modifier.height(IntrinsicSize.Min)) {
                    Box(Modifier.width(3.dp).fillMaxHeight().background(MaterialTheme.colorScheme.primary))
                    Text(inline(block.text), style = typography.bodyMedium, fontStyle = FontStyle.Italic, modifier = Modifier.padding(start = 10.dp))
                }
                is MdBlock.Code -> Box(
                    Modifier.fillMaxWidth().background(codeBg, RoundedCornerShape(6.dp)).horizontalScroll(rememberScrollState()).padding(10.dp),
                ) { Text(block.text, fontFamily = FontFamily.Monospace, style = typography.bodySmall) }
                is MdBlock.ListBlock -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    block.items.forEachIndexed { index, item ->
                        Row {
                            Text(if (block.ordered) "${block.start + index}." else "•", style = typography.bodyMedium, modifier = Modifier.width(24.dp))
                            Text(inline(item), style = typography.bodyMedium)
                        }
                    }
                }
                MdBlock.Rule -> HorizontalDivider()
            }
        }
    }
}
