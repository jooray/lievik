package today.cypherpunk.lievik.ui

import org.junit.Assert.assertEquals
import org.junit.Test
import today.cypherpunk.lievik.ui.components.MarkdownParser
import today.cypherpunk.lievik.ui.components.MdBlock
import today.cypherpunk.lievik.ui.components.MdInline
import today.cypherpunk.lievik.ui.screens.channels.stripJsonBlocks

class MarkdownParserTest {
    @Test
    fun blocks() {
        val md = "# Title\n\nPara one\nstill one\n\n- a\n- b\n\n1. x\n2. y\n\n> quote\n\n```\ncode\n```\n\n---"
        assertEquals(
            listOf(
                MdBlock.Heading(1, "Title"),
                MdBlock.Paragraph("Para one\nstill one"),
                MdBlock.ListBlock(listOf("a", "b"), ordered = false),
                MdBlock.ListBlock(listOf("x", "y"), ordered = true, start = 1),
                MdBlock.Quote("quote"),
                MdBlock.Code("code"),
                MdBlock.Rule,
            ),
            MarkdownParser.blocks(md),
        )
    }

    @Test
    fun inline() {
        assertEquals(
            listOf(
                MdInline.Bold(listOf(MdInline.Plain("bold"))),
                MdInline.Plain(" and "),
                MdInline.Italic(listOf(MdInline.Plain("it"))),
                MdInline.Plain(" "),
                MdInline.Link(listOf(MdInline.Plain("link")), "https://x.example"),
                MdInline.Plain(" "),
                MdInline.Code("c"),
            ),
            MarkdownParser.inline("**bold** and *it* [link](https://x.example) `c`"),
        )
        // snake_case words are not italics
        assertEquals(listOf(MdInline.Plain("a_b_c")), MarkdownParser.inline("a_b_c"))
        assertEquals(MdInline.Link(listOf(MdInline.Plain("https://x.example/p")), "https://x.example/p"), MarkdownParser.inline("see https://x.example/p.")[1])
    }

    @Test
    fun proposalJsonIsHiddenFromTheChatText() {
        assertEquals("Here you go:", stripJsonBlocks("Here you go:\n```json\n{\"channels\":[]}\n```"))
    }
}
