package today.cypherpunk.lievik.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import today.cypherpunk.lievik.data.DbFixtures.channel
import today.cypherpunk.lievik.data.DbFixtures.event
import today.cypherpunk.lievik.data.DbFixtures.rating
import today.cypherpunk.lievik.data.DbFixtures.source
import today.cypherpunk.lievik.data.db.EventsQuery
import today.cypherpunk.lievik.data.db.LievikDao
import today.cypherpunk.lievik.data.db.LievikDatabase
import today.cypherpunk.lievik.data.db.SyncMerge

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = android.app.Application::class)
class SyncMergeTest {
    private lateinit var db: LievikDatabase
    private lateinit var dao: LievikDao

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), LievikDatabase::class.java).allowMainThreadQueries().build()
        dao = db.dao()
    }

    @After fun tearDown() = db.close()

    private fun eventIds() = runBlocking { dao.events(EventsQuery().toSqlite()).first().map { it.id }.sorted() }
    private fun ratingIds() = runBlocking { (1L..20L).flatMap { dao.channelEventsForEvent(it).first() }.map { it.id }.sorted() }

    @Test
    fun pureRemovedIds() {
        assertEquals(listOf(2L), SyncMerge.removed(listOf(1, 2, 3), listOf(1, 3, 4)))
        assertEquals(emptyList<Long>(), SyncMerge.removed(emptyList(), listOf(1)))
    }

    @Test
    fun removedSourceTakesItsEventsAndTheirRatingsAlong() = runBlocking {
        // First page: two sources (one manual), two channels.
        dao.applySyncPage(
            sources = listOf(source(1), source(2), source(9, "manual")),
            channels = listOf(channel(10), channel(11)),
            events = listOf(event(1, 1), event(2, 2), event(3, 9)),
            channelEvents = listOf(rating(101, 10, 1, 80), rating(102, 10, 2, 80), rating(103, 11, 3, 80)),
        )
        assertEquals(listOf(1L, 2L, 3L), eventIds())

        // Source 2 was deleted on the server; incremental page has no events.
        dao.applySyncPage(listOf(source(1), source(9, "manual")), listOf(channel(10), channel(11)), emptyList(), emptyList())
        assertEquals(listOf(1L, 3L), eventIds())
        assertEquals(listOf(101L, 103L), ratingIds())
        assertEquals(listOf(1L, 9L), dao.sourceIds().sorted())
    }

    @Test
    fun removedChannelTakesItsRatingsButNotTheEvents() = runBlocking {
        dao.applySyncPage(listOf(source(1)), listOf(channel(10), channel(11)), listOf(event(1, 1)), listOf(rating(101, 10, 1, 80), rating(102, 11, 1, 70)))
        dao.applySyncPage(listOf(source(1)), listOf(channel(10)), emptyList(), emptyList())
        assertEquals(listOf(1L), eventIds())
        assertEquals(listOf(101L), ratingIds())
        assertEquals(listOf(10L), dao.channelIds())
    }

    @Test
    fun upsertsAreIdempotentAcrossTheOverlapWindow() = runBlocking {
        val page = listOf(rating(101, 10, 1, 80))
        dao.applySyncPage(listOf(source(1)), listOf(channel(10)), listOf(event(1, 1)), page)
        dao.applySyncPage(listOf(source(1)), listOf(channel(10)), listOf(event(1, 1, "edited")), listOf(rating(101, 10, 1, 90, used = true)))
        assertEquals("edited", dao.event(1).first()!!.content)
        val r = dao.channelEventsForEvent(1).first().single()
        assertEquals(90, r.relevanceScore)
        assertEquals(true, r.used)
    }
}
