package ai.zetic.realtimetranslate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * The catalog rules, enforced across every value in every language rather than across the copy
 * constants somebody remembered to list.
 *
 * These read the three `strings.xml` files off disk on purpose. A test that walked the generated
 * `R.string` fields would only ever see the default language, which is exactly the one that cannot
 * be wrong.
 */
class LocalizationCatalogTest {

    @Test fun `no user-facing string in any language contains an em dash or an en dash`() {
        catalogs.forEach { (language, strings) ->
            strings.forEach { (key, value) ->
                DASHES.forEach { dash ->
                    assertTrue(
                        "$language/$key contains ${dash.name}: $value",
                        !value.contains(dash.character),
                    )
                }
            }
        }
    }

    @Test fun `every key the default language defines is translated in French and Spanish`() {
        // `app_name` is the product name, which is never translated and so is never overridden.
        val expected = catalogs.getValue("en").keys - "app_name"
        assertEquals(expected, catalogs.getValue("fr").keys)
        assertEquals(expected, catalogs.getValue("es").keys)
    }

    @Test fun `no language defines a key the default language does not`() {
        val known = catalogs.getValue("en").keys
        listOf("fr", "es").forEach { language ->
            assertEquals(emptySet<String>(), catalogs.getValue(language).keys - known)
        }
    }

    @Test fun `every translation carries the same format arguments as the English it replaces`() {
        val english = catalogs.getValue("en")
        listOf("fr", "es").forEach { language ->
            catalogs.getValue(language).forEach { (key, value) ->
                assertEquals(
                    "$language/$key format arguments differ from English",
                    specifiers(english.getValue(key)),
                    specifiers(value),
                )
            }
        }
    }

    @Test fun `every format argument is positional, so a translation may reorder them`() {
        catalogs.forEach { (language, strings) ->
            strings.forEach { (key, value) ->
                val nonPositional: List<String> =
                    NON_POSITIONAL.findAll(value.replace("%%", "")).map { it.value }.toList()
                assertEquals("$language/$key uses a non-positional specifier", emptyList<String>(), nonPositional)
            }
        }
    }

    @Test fun `French keeps its typographic spacing and its apostrophes`() {
        val french = catalogs.getValue("fr")
        // A no-break space before every colon, and before the literal percent sign.
        french.forEach { (key, value) ->
            assertTrue("fr/$key has a plain space before a colon", !value.contains(" :"))
            assertTrue("fr/$key has an ASCII apostrophe", !value.contains('\''))
        }
        assertTrue(french.getValue("first_run_priming_microphone").contains("Micro :"))
        assertTrue(french.getValue("banner_loading_model").contains("%1\$d %%"))
        assertTrue(french.getValue("settings_app_language_title").contains('’'))
    }

    @Test fun `Spanish says Empezar rather than Iniciar sesion for starting a conversation`() {
        val spanish = catalogs.getValue("es")
        assertTrue(spanish.getValue("session_start").startsWith("Empezar"))
        spanish.forEach { (key, value) ->
            assertTrue("es/$key says Iniciar sesion, which means log in", !value.contains("Iniciar sesi"))
        }
    }

    private companion object {
        val DASHES = listOf(
            Dash("em dash", '—'),
            Dash("en dash", '–'),
            Dash("minus sign", '−'),
        )

        /** `%s`, `%d` and friends without an argument index. `%%` is a literal and is removed first. */
        val NON_POSITIONAL = Regex("%[^%\\d]")

        val SPECIFIER = Regex("%(\\d+\\$[a-zA-Z]|%)")

        fun specifiers(value: String): List<String> =
            SPECIFIER.findAll(value).map { it.value }.toList().sorted()

        val catalogs: Map<String, Map<String, String>> = mapOf(
            "en" to read("values"),
            "fr" to read("values-fr"),
            "es" to read("values-es"),
        )

        /**
         * Read as XML rather than as text: the file escapes apostrophes for the Android resource
         * compiler, and only the parsed value is what a person actually sees.
         */
        fun read(directory: String): Map<String, String> {
            val file = File("src/main/res/$directory/strings.xml")
            assertTrue("missing ${file.path}", file.isFile)
            val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
            val nodes = document.getElementsByTagName("string")
            return (0 until nodes.length).associate { index ->
                val node = nodes.item(index)
                val name = node.attributes.getNamedItem("name").nodeValue
                // The resource compiler strips the quoting a value uses to keep its edge spaces.
                name to node.textContent.removeSurrounding("\"").replace("\\'", "'")
            }
        }
    }

    private data class Dash(val name: String, val character: Char)
}
