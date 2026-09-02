package ai.zetic.realtimetranslate

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.platform.LocalContext

/**
 * A string a person reads, carried as what it is rather than as text.
 *
 * Composables can call `stringResource` directly, but the view model, the recognizer, and the
 * translation runtime all produce text long before a composition exists, and Turn Translate can be
 * put into a language of its own at any moment. Resolving those strings where they are built would
 * freeze them in the language that was in force when the session started. Carrying the resource id
 * instead defers every resolution to the frame that draws it, so a language change repaints the
 * whole screen, error banners included.
 *
 * [Raw] is for the one kind of text that is already a string and never a key: a message the
 * platform or the Melange runtime produced, which this app cannot translate and must not mangle.
 */
@Immutable
sealed interface UiText {
    @Immutable
    data class Raw(val value: String) : UiText

    /**
     * @param args may themselves be [UiText], so a sentence can be composed from a phrase that is
     * also translated (`The translation model is about 1.9 GB.` is two entries, not one).
     */
    @Immutable
    data class Res(@StringRes val id: Int, val args: List<Any> = emptyList()) : UiText

    fun resolve(context: Context): String = when (this) {
        is Raw -> value
        is Res -> context.getString(id, *args.map { if (it is UiText) it.resolve(context) else it }.toTypedArray())
    }

    companion object {
        fun raw(value: String): UiText = Raw(value)
        fun res(@StringRes id: Int, vararg args: Any): UiText = Res(id, args.toList())
    }
}

/** Resolves against the composition's own context, so it follows the app's current language. */
@Composable
fun UiText.text(): String = resolve(LocalContext.current)
