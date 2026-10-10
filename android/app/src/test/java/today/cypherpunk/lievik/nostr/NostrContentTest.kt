package today.cypherpunk.lievik.nostr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import today.cypherpunk.lievik.data.api.Reference

class NostrContentTest {
    private val npub = "nostr:npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m"
    private val nevent = "nostr:nevent1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhkummn9ekx7mqpz3mhxue69uhhyetvv9ujuerpd46hxtnfduq3vamnwvaz7tmjv4kxz7fwdehhxarj9e3xzmnyqyv8wumn8ghj7un9d3shjtnndehhyapwwdhkx6tpdsq36amnwvaz7tmwdaehgu3dwp6kytnhv4kxcmmjv3jhytnwv46q"
    private val naddr = "nostr:naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld"

    @Test
    fun replacesProfilesNotesAndArticlesByUri() {
        val content = "Hi $npub look at this $nevent and read $naddr!"
        val refs = listOf(
            Reference(npub, "profile", "@Alice", url = "https://example.com/p/alice"),
            Reference(nevent, "event", "Bob", preview = "the quoted note", url = "https://example.com/e/1"),
            Reference(naddr, "article", "My Article", url = "https://example.com/a/1"),
        )
        val segments = NostrContent.parse(content, refs)
        assertEquals(
            listOf(
                Segment.Text("Hi "),
                Segment.Mention("@Alice", "https://example.com/p/alice"),
                Segment.Text(" look at this "),
                Segment.Quote("Bob", "the quoted note", "https://example.com/e/1"),
                Segment.Text(" and read "),
                Segment.Article("My Article", "https://example.com/a/1"),
                Segment.Text("!"),
            ),
            segments,
        )
    }

    @Test
    fun unresolvedReferencesFallBack() {
        val segments = NostrContent.parse("by $npub", emptyList())
        assertEquals(Segment.Unresolved(npub, isProfile = true), segments.last())
        val note = NostrContent.parse(nevent, emptyList())
        assertEquals(listOf(Segment.Unresolved(nevent, isProfile = false)), note)
        assertTrue(NostrContent.shortNpub(npub).startsWith("@npub1sg6p"))
    }

    @Test
    fun linksAndImagesAreSplitOutAndTrailingPunctuationIsKept() {
        val segments = NostrContent.parse("See https://lievik.example/x. And https://img.example/a.jpg", emptyList())
        assertEquals(
            listOf(
                Segment.Text("See "),
                Segment.Link("https://lievik.example/x"),
                Segment.Text(". And "),
                Segment.Image("https://img.example/a.jpg"),
            ),
            segments,
        )
    }

    @Test
    fun listedImagesNotInTheTextAreAppendedOnce() {
        val segments = NostrContent.parse("text https://cdn.example/1.png", emptyList(), images = listOf("https://cdn.example/1.png", "https://cdn.example/imeta"))
        assertEquals(Segment.Image("https://cdn.example/1.png"), segments[1])
        assertEquals(Segment.Image("https://cdn.example/imeta"), segments.last())
        assertEquals(3, segments.size)
    }

    @Test
    fun plainTextResolvesForPreviews() {
        val refs = listOf(Reference(npub, "profile", "@Alice"), Reference(nevent, "event", "Bob", preview = "quoted"))
        assertEquals("@Alice says [quoted]", NostrContent.plainText("$npub says $nevent", refs, "[referenced note]"))
        assertEquals("[referenced note]", NostrContent.plainText(nevent, emptyList(), "[referenced note]"))
    }
}
