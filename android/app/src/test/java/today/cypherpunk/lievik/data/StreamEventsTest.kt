package today.cypherpunk.lievik.data

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import today.cypherpunk.lievik.data.api.ApiClient
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.api.StreamEvent
import today.cypherpunk.lievik.data.api.StreamEvents

class StreamEventsTest {
    @Test
    fun decodesEachEventType() {
        assertEquals(StreamEvent.Phase("humanizing"), StreamEvents.decode("phase", """{"phase":"humanizing"}"""))
        assertEquals(StreamEvent.Chunk("Hello \"world\"\n"), StreamEvents.decode("chunk", "\"Hello \\\"world\\\"\\n\""))
        assertEquals(StreamEvent.Chunk("raw"), StreamEvents.decode("chunk", "raw"))
        val proposal = StreamEvents.decode(
            "proposal",
            """{"channels":[{"name":"News","language":"sk","content_style":"short","settings":{"relevance_threshold":70}}],"templates":[{"name":"T","template":"# t"}]}""",
        ) as StreamEvent.ProposalReady
        assertEquals("News", proposal.proposal.channels.single().name)
        assertEquals(70, proposal.proposal.channels.single().settings.relevanceThreshold)
        assertEquals("short", proposal.proposal.channels.single().contentStyle)
        assertEquals("T", proposal.proposal.templates.single().name)
        val complete = StreamEvents.decode("complete", """{"success":true,"cited_events":[{"id":5,"content":"c","source_name":"S","published_at":"2026-10-09T12:00:00Z"}]}""") as StreamEvent.Complete
        assertTrue(complete.success)
        assertEquals(5L, complete.citedEvents.single().id)
        assertEquals("S", complete.citedEvents.single().sourceName)
        assertEquals(StreamEvent.Failed("boom"), StreamEvents.decode("error", """{"message":"boom"}"""))
        assertNull(StreamEvents.decode("future_event", "{}"))
    }

    private lateinit var server: MockWebServer

    @Before fun start() { server = MockWebServer(); server.start() }
    @After fun stop() { server.close() }

    private fun client() = ApiClient({ server.url("/").toString() }, { "lvk_test" }, { "sk" }, "test", {})

    @Test
    fun streamsOverHttp() = runBlocking {
        server.enqueue(
            MockResponse.Builder().addHeader("Content-Type", "text/event-stream").body(
                "event: phase\ndata: {\"phase\":\"generating\"}\n\nevent: chunk\ndata: \"Hel\"\n\nevent: chunk\ndata: \"lo\"\n\nevent: complete\ndata: {\"success\":true}\n\n",
            ).build(),
        )
        val events = client().stream("channels/1/contents/2/generate", JsonObject(emptyMap())).toList()
        assertEquals(StreamEvent.Phase("generating"), events[0])
        assertEquals("Hello", events.filterIsInstance<StreamEvent.Chunk>().joinToString("") { it.text })
        assertTrue(events.last() is StreamEvent.Complete)
        val request = server.takeRequest()
        assertEquals("/api/v1/channels/1/contents/2/generate", request.url.encodedPath)
        assertEquals("Bearer lvk_test", request.headers["Authorization"])
        assertEquals("sk", request.headers["Accept-Language"])
    }

    @Test
    fun billingDenialBeforeTheStreamIsAnApiError() = runBlocking {
        server.enqueue(
            MockResponse.Builder().code(402).addHeader("Content-Type", "application/json")
                .body("""{"error":"Trial needed","code":"paywall"}""").build(),
        )
        val error = runCatching { client().stream("chat/stream", JsonObject(emptyMap())).toList() }.exceptionOrNull()
        assertEquals(ApiError.Paywall("Trial needed", null), error)
    }

    @Test
    fun serverBaseKeepsAPathPrefix() {
        assertEquals("https://h.example/lievik/api/v1/", ApiClient.apiBase("https://h.example/lievik/").toString())
        assertEquals("https://h.example/api/v1/", ApiClient.apiBase("https://h.example").toString())
        assertNull(ApiClient.apiBase("not a url"))
    }
}
