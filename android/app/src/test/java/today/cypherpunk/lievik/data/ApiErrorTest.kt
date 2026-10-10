package today.cypherpunk.lievik.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import today.cypherpunk.lievik.R
import today.cypherpunk.lievik.data.api.ApiError
import today.cypherpunk.lievik.data.repo.Messages
import today.cypherpunk.lievik.data.repo.UiMessage
import java.io.IOException

class ApiErrorTest {
    @Test
    fun billingDenialsMapToTheirTypes() {
        val paywall = ApiError.fromResponse(402, """{"error":"Needs a trial","code":"paywall","billing_url":"https://x/billing"}""")
        assertEquals(ApiError.Paywall("Needs a trial", "https://x/billing"), paywall)
        assertEquals(ApiError.DailyCap("cap"), ApiError.fromResponse(429, """{"error":"cap","code":"daily_cap"}"""))
        assertEquals(ApiError.BillingUnavailable("down"), ApiError.fromResponse(503, """{"error":"down","code":"billing_unavailable"}"""))
        listOf(paywall, ApiError.DailyCap(null), ApiError.BillingUnavailable(null)).forEach {
            assertTrue(it.isBillingDenial)
            assertTrue(Messages.forError(it) is UiMessage.BillingDenial)
        }
        assertEquals(R.string.billing_daily_cap, Messages.denialText(ApiError.DailyCap(null)))
        assertEquals(R.string.billing_unavailable, Messages.denialText(ApiError.BillingUnavailable(null)))
        assertEquals(R.string.billing_paywall, Messages.denialText(ApiError.Paywall(null, null)))
    }

    @Test
    fun otherStatusesAndCodes() {
        assertEquals(ApiError.Unauthorized("no"), ApiError.fromResponse(401, """{"error":"no","code":"unauthorized"}"""))
        assertEquals(ApiError.RateLimited("slow", 30), ApiError.fromResponse(429, """{"error":"slow","code":"rate_limited"}""", "30"))
        assertEquals(ApiError.NotFound("gone"), ApiError.fromResponse(404, """{"error":"gone","code":"not_found"}"""))
        val invalid = ApiError.fromResponse(422, """{"error":"Bad","code":"invalid","details":{"name":["can't be blank"],"identifier":["is bad","too short"]}}""")
        assertTrue(invalid is ApiError.Validation)
        invalid as ApiError.Validation
        assertEquals(listOf("is bad", "too short"), invalid.details["identifier"])
        assertEquals("invalid", invalid.code)
        assertEquals(ApiError.Validation("Nothing selected", "no_selection"), ApiError.fromResponse(422, """{"error":"Nothing selected","code":"no_selection"}"""))
        assertEquals(ApiError.Refused(503, "busy", "Busy"), ApiError.fromResponse(503, """{"error":"Busy","code":"busy"}"""))
        assertEquals(ApiError.Server(502, null), ApiError.fromResponse(502, "<html>bad gateway</html>"))
    }

    @Test
    fun throwablesMap() {
        assertEquals(ApiError.Network, ApiError.from(IOException("down")))
        val validation = ApiError.Validation("x", "invalid")
        assertEquals(validation, ApiError.from(validation))
        assertTrue(Messages.forError(ApiError.Network) == UiMessage.Res(R.string.error_network))
        assertEquals(UiMessage.Text("Bad"), Messages.forError(ApiError.Validation("Bad", "invalid")))
    }
}
