package today.cypherpunk.lievik.ui.nav

/** Navigation routes. Literal routes ("sources/new") never collide with "{id}" ones. */
object Routes {
    const val DASHBOARD = "dashboard"
    const val CHANNELS = "channels"
    const val EVENTS = "events"
    const val ASK = "ask"
    const val MORE = "more"

    const val SOURCES = "sources"
    const val SOURCE_NEW = "sources/new"
    const val SOURCE = "source/{id}"
    const val SOURCE_EDIT = "source/{id}/edit"
    fun source(id: Long) = "source/$id"
    fun sourceEdit(id: Long) = "source/$id/edit"

    const val CHANNEL_NEW = "channels/new"
    const val CHANNELS_AI = "channels/ai"
    const val CHANNEL = "channel/{id}?selected={selected}"
    const val CHANNEL_EDIT = "channel/{id}/edit"
    const val CONTENTS = "channel/{id}/contents"
    const val CONTENT_NEW = "channel/{id}/contents/new?ids={ids}"
    const val CONTENT = "channel/{cid}/content/{id}?generate={generate}"
    /** [selectedEvent] comes first in the queue, already selected, as on the web (?selected_event=). */
    fun channel(id: Long, selectedEvent: Long? = null) = "channel/$id" + (selectedEvent?.let { "?selected=$it" } ?: "")
    fun channelEdit(id: Long) = "channel/$id/edit"
    fun contents(channelId: Long) = "channel/$channelId/contents"
    fun contentNew(channelId: Long, eventIds: Collection<Long>) = "channel/$channelId/contents/new?ids=${eventIds.joinToString(",")}"
    fun content(channelId: Long, id: Long, generate: Boolean = false) = "channel/$channelId/content/$id?generate=$generate"

    const val EVENT = "event/{id}"
    fun event(id: Long) = "event/$id"
    const val MANUAL_EVENT = "events/manual"

    const val ACTIVITY = "activity"
    const val DEV_LOGS = "activity/{id}/dev_logs"
    fun devLogs(id: Long) = "activity/$id/dev_logs"

    const val SETTINGS = "settings"
    const val TEMPLATES = "settings/templates"
    const val TOKENS = "settings/tokens"
    const val BILLING = "billing"

    /** Which bottom-bar tab a route belongs to. */
    fun tabOf(route: String?): String = when {
        route == null -> DASHBOARD
        route == DASHBOARD -> DASHBOARD
        route.startsWith("channel") -> CHANNELS
        route.startsWith("event") -> EVENTS
        route == ASK -> ASK
        else -> MORE
    }

    /** Which side-rail entry a route belongs to, when the rail lists every destination (no More). */
    fun railItemOf(route: String?): String = when {
        route == null -> DASHBOARD
        route == CHANNELS_AI -> CHANNELS_AI
        route == MANUAL_EVENT -> MANUAL_EVENT
        route.startsWith("source") -> SOURCES
        route.startsWith("activity") -> ACTIVITY
        route.startsWith("settings") -> SETTINGS
        route == BILLING -> BILLING
        else -> tabOf(route)
    }
}
