package today.cypherpunk.lievik.data.api

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/** One server-sent event from an AI stream, decoded. */
sealed interface StreamEvent {
    /** generating | humanizing | refining */
    data class Phase(val phase: String) : StreamEvent

    /** A text fragment to append. */
    data class Chunk(val text: String) : StreamEvent

    /** AI channel chat: a structured channel proposal. */
    data class ProposalReady(val proposal: Proposal) : StreamEvent

    data class Complete(val data: JsonObject) : StreamEvent {
        val success: Boolean get() = data["success"]?.jsonPrimitive?.contentOrNull != "false"
        val citedEvents: List<CitedEvent>
            get() = runCatching {
                data["cited_events"]?.let { ApiJson.decodeFromJsonElement(kotlinx.serialization.builtins.ListSerializer(CitedEvent.serializer()), it) }
            }.getOrNull().orEmpty()
        val errorMessage: String? get() = data["error"]?.jsonPrimitive?.contentOrNull
    }

    data class Failed(val message: String?) : StreamEvent
}

object StreamEvents {
    /**
     * Decodes one event as the web's Stimulus controllers do. `chunk` data is
     * a JSON string; a server that sends it raw is tolerated. Unknown event
     * types are ignored (null), so the server can add new ones.
     */
    fun decode(type: String?, data: String): StreamEvent? = when (type ?: "message") {
        "phase" -> runCatching { ApiJson.parseToJsonElement(data) as JsonObject }.getOrNull()
            ?.get("phase")?.jsonPrimitive?.contentOrNull?.let { StreamEvent.Phase(it) }
        "chunk", "message" -> StreamEvent.Chunk(
            runCatching { (ApiJson.parseToJsonElement(data) as JsonPrimitive).takeIf { it.isString }?.content }.getOrNull() ?: data,
        )
        "proposal" -> runCatching { StreamEvent.ProposalReady(ApiJson.decodeFromString(Proposal.serializer(), data)) }.getOrNull()
        "complete" -> StreamEvent.Complete(
            runCatching { ApiJson.parseToJsonElement(data) as JsonObject }.getOrNull() ?: JsonObject(emptyMap()),
        )
        "error" -> StreamEvent.Failed(
            runCatching { ApiJson.parseToJsonElement(data).errorMessage() }.getOrNull()
                ?: data.takeIf { it.isNotBlank() && !it.trimStart().startsWith("{") },
        )
        else -> null
    }
}
