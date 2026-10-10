package today.cypherpunk.lievik.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import today.cypherpunk.lievik.data.DbFixtures.channel
import today.cypherpunk.lievik.data.DbFixtures.event
import today.cypherpunk.lievik.data.DbFixtures.rating
import today.cypherpunk.lievik.data.DbFixtures.source
import today.cypherpunk.lievik.data.db.CurationQuery
import today.cypherpunk.lievik.data.db.CurationSort
import today.cypherpunk.lievik.data.db.EventsQuery
import today.cypherpunk.lievik.data.db.LievikDao
import today.cypherpunk.lievik.data.db.LievikDatabase

/** The local curation queue must match the web's ChannelsController#show. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = android.app.Application::class)
class CurationQueryTest {
    private lateinit var db: LievikDatabase
    private lateinit var dao: LievikDao

    @Before
    fun setUp() = runBlocking {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), LievikDatabase::class.java).allowMainThreadQueries().build()
        dao = db.dao()
        dao.upsertSources(listOf(source(1)))
        dao.upsertChannels(listOf(channel(10, threshold = 50), channel(11)))
        dao.upsertEvents(
            listOf(
                event(1, 1, "about bitcoin", publishedAt = 1000),
                event(2, 1, "about nostr 100% sure", publishedAt = 3000),
                event(3, 1, "below the bar", publishedAt = 2000),
                event(4, 1, "already used bitcoin", publishedAt = 4000),
                event(5, 1, "unrated", publishedAt = 5000),
                event(6, 1, "other channel", publishedAt = 6000),
            ),
        )
        dao.upsertChannelEvents(
            listOf(
                rating(101, 10, 1, 90),
                rating(102, 10, 2, 60),
                rating(103, 10, 3, 49),
                rating(104, 10, 4, 95, used = true),
                rating(105, 10, 5, null),
                rating(106, 11, 6, 99),
            ),
        )
    }

    @After fun tearDown() = db.close()

    private fun run(q: CurationQuery) = runBlocking { dao.curation(q.toSqlite()).first().map { it.event.id } }

    @Test
    fun aboveThresholdUnusedOnlyByRelevance() {
        assertEquals(listOf(1L, 2L), run(CurationQuery(10, 50)))
    }

    @Test
    fun showUsedPinsUsedToTheBottomWhateverTheSort() {
        assertEquals(listOf(1L, 2L, 4L), run(CurationQuery(10, 50, showUsed = true)))
        assertEquals(listOf(2L, 1L, 4L), run(CurationQuery(10, 50, showUsed = true, sort = CurationSort.Newest)))
        assertEquals(listOf(1L, 2L, 4L), run(CurationQuery(10, 50, showUsed = true, sort = CurationSort.Oldest)))
    }

    @Test
    fun sortsByPublishedTime() {
        assertEquals(listOf(2L, 1L), run(CurationQuery(10, 50, sort = CurationSort.Newest)))
        assertEquals(listOf(1L, 2L), run(CurationQuery(10, 50, sort = CurationSort.Oldest)))
    }

    @Test
    fun thresholdChangesTheSet() {
        assertEquals(listOf(1L, 2L, 3L), run(CurationQuery(10, 0)))
        assertEquals(listOf(1L), run(CurationQuery(10, 61)))
    }

    @Test
    fun searchIsASubstringWithEscapedWildcards() {
        assertEquals(listOf(1L), run(CurationQuery(10, 50, search = "bitcoin")))
        assertEquals(listOf(1L, 4L), run(CurationQuery(10, 50, showUsed = true, search = "BITCOIN")))
        // "%" is literal, not "match everything".
        assertEquals(listOf(2L), run(CurationQuery(10, 50, search = "100%")))
        assertTrue(run(CurationQuery(10, 50, search = "%")).size == 1)
    }

    @Test
    fun countsAndOptimisticToggle() = runBlocking {
        val counts = dao.usageCounts(10, 50).first()
        assertEquals(2, counts.unused)
        assertEquals(1, counts.used)
        val before = dao.channelEventsFor(10, listOf(1))
        dao.setUsed(10, listOf(1), true, "2026-10-09T00:00:00Z")
        assertEquals(listOf(2L), run(CurationQuery(10, 50)))
        dao.upsertChannelEvents(before) // rollback
        assertEquals(listOf(1L, 2L), run(CurationQuery(10, 50)))
    }

    @Test
    fun eventsListFilters() = runBlocking {
        val all = dao.events(EventsQuery().toSqlite()).first().map { it.id }
        assertEquals(listOf(6L, 5L, 4L, 2L, 3L, 1L), all)
        assertEquals(listOf(4L, 1L), dao.events(EventsQuery(search = "bitcoin").toSqlite()).first().map { it.id })
        assertEquals(emptyList<Long>(), dao.events(EventsQuery(sourceId = 99).toSqlite()).first().map { it.id })
    }

    @Test
    fun sqlShape() {
        val q = CurationQuery(10, 50, search = "a_b!")
        assertTrue(q.sql().contains("ce_used = 0"))
        assertEquals("%a!_b!!%", q.args()[2])
        assertTrue(!CurationQuery(10, 50, showUsed = true).sql().contains("ce_used = 0"))
    }
}
