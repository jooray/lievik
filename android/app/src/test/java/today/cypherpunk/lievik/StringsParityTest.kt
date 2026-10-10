package today.cypherpunk.lievik

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Every string exists in en, sk, cs and es with the same placeholders, and
 * every plural has the forms its language needs (sk/cs: one, few, many,
 * other) — the app's twin of the web's spec/i18n/locale_files_spec.rb.
 */
class StringsParityTest {
    private val res = listOf(File("src/main/res"), File("app/src/main/res")).first { it.exists() }
    private val locales = listOf("sk", "cs", "es")
    private val placeholder = Regex("""%(\d+\$)?[sdf]""")
    private val requiredPlurals = mapOf(
        "en" to setOf("one", "other"),
        "sk" to setOf("one", "few", "many", "other"),
        "cs" to setOf("one", "few", "many", "other"),
        "es" to setOf("one", "other"),
    )

    private data class Entry(val text: String?, val plurals: Map<String, String>?)

    private fun read(file: File): Map<String, Entry> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val out = linkedMapOf<String, Entry>()
        val strings = doc.getElementsByTagName("string")
        for (i in 0 until strings.length) {
            val e = strings.item(i) as Element
            if (e.getAttribute("translatable") == "false") continue
            out[e.getAttribute("name")] = Entry(e.textContent, null)
        }
        val plurals = doc.getElementsByTagName("plurals")
        for (i in 0 until plurals.length) {
            val e = plurals.item(i) as Element
            val items = e.getElementsByTagName("item")
            out[e.getAttribute("name")] = Entry(null, (0 until items.length).associate {
                val item = items.item(it) as Element
                item.getAttribute("quantity") to item.textContent
            })
        }
        return out
    }

    private fun placeholders(entry: Entry): Set<String> =
        (entry.plurals?.get("other")?.let { listOf(it) } ?: listOf(entry.text.orEmpty()))
            .flatMap { placeholder.findAll(it.replace("%%", "")).map { m -> m.value } }.toSet()

    @Test
    fun everyStringExistsInEveryLanguage() {
        val englishFiles = File(res, "values").listFiles { f -> f.name.startsWith("strings") }!!
        assertTrue(englishFiles.isNotEmpty())
        for (englishFile in englishFiles) {
            val english = read(englishFile)
            if (english.isEmpty()) continue
            for (locale in locales) {
                val file = File(res, "values-$locale/${englishFile.name}")
                assertTrue("values-$locale/${englishFile.name} is missing", file.exists())
                val translated = read(file)
                assertTrue("$locale lacks ${(english.keys - translated.keys).take(10)}", (english.keys - translated.keys).isEmpty())
                assertTrue("$locale has extra ${(translated.keys - english.keys).take(10)}", (translated.keys - english.keys).isEmpty())
                english.forEach { (name, entry) ->
                    val other = translated.getValue(name)
                    assertEquals("$locale $name changes placeholders", placeholders(entry), placeholders(other))
                }
            }
        }
    }

    @Test
    fun pluralsHaveTheFormsEachLanguageNeeds() {
        var count = 0
        for (locale in listOf("en") + locales) {
            val dir = File(res, if (locale == "en") "values" else "values-$locale")
            dir.listFiles { f -> f.name.startsWith("strings") }!!.forEach { file ->
                read(file).filterValues { it.plurals != null }.forEach { (name, entry) ->
                    count++
                    val missing = requiredPlurals.getValue(locale) - entry.plurals!!.keys
                    assertTrue("$locale plural $name lacks $missing", missing.isEmpty())
                }
            }
        }
        assertTrue("no plurals found", count > 0)
    }
}
