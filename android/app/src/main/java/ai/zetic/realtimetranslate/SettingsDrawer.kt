package ai.zetic.realtimetranslate

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The only secondary surface. It slides in from the trailing edge over the main screen, which
 * stays mounted and untouched behind a dim scrim. Opening it never changes session state; the one
 * row that changes anything, `Clear conversation`, empties the transcript and leaves the session,
 * the model, and both language chips exactly as they were.
 */

/** The About block's facts, read from the installed package so the drawer never hardcodes them. */
data class AppInfo(val displayName: String, val version: String, val build: String) {
    /** One terse line for the About block: `Version 0.1.0 (1)`. */
    val versionLine: String get() = "Version $version ($build)"

    companion object {
        /**
         * `PackageInfo` rather than `BuildConfig` for the version pair, so the drawer reports what
         * is actually installed on the phone. `BuildConfig` is the fallback for the one case where
         * the package manager cannot answer about the app's own package.
         */
        fun from(context: Context): AppInfo {
            val packageManager = context.packageManager
            val label = runCatching { context.applicationInfo.loadLabel(packageManager).toString() }
                .getOrNull()
                ?.takeIf { it.isNotBlank() }
                ?: FirstRunCopy.PRODUCT_NAME
            @Suppress("DEPRECATION")
            val info = runCatching { packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
            val version = info?.versionName?.takeIf { it.isNotBlank() } ?: BuildConfig.VERSION_NAME
            val build = info?.let {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                    it.longVersionCode.toString()
                } else {
                    @Suppress("DEPRECATION") it.versionCode.toString()
                }
            } ?: BuildConfig.VERSION_CODE.toString()
            return AppInfo(displayName = label, version = version, build = build)
        }

        fun unavailable(): AppInfo = AppInfo(FirstRunCopy.PRODUCT_NAME, BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString())
    }
}

/** Every drawer string in one place, in the app's terse voice and with no em dash anywhere. */
object SettingsDrawerCopy {
    /** An address and a URL, so neither is ever translated by accident. */
    const val CONTACT_EMAIL = "contact@zetic.ai"
    const val WEBSITE = "https://zetic.ai"

    const val TITLE = "Settings"
    const val CLOSE = "Close settings"

    const val CLEAR_TITLE = "Clear conversation"
    const val CLEAR_SUBTITLE = "Keeps the session and the languages"
    const val CLEAR_CONFIRMATION = "Conversation cleared"

    const val WEBSITE_TITLE = "Visit zetic.ai"
    const val CONTACT_TITLE = "Contact us"
    const val COPY_CONFIRMATION = "Email address copied"
    const val BUBBLE_COPY_ACTION = "Copy"
    const val BUBBLE_COPY_CONFIRMATION = "Copied"

    const val ABOUT_TITLE = "About"
    const val PRIVACY_LINE = "Speech, translation, everything stays on this phone."

    /**
     * Spelled out here so the accessibility label and the visible row can never disagree about the
     * fixed words between them.
     */
    fun clearAccessibilityLabel(isEnabled: Boolean): String =
        if (isEnabled) "$CLEAR_TITLE, keeps the session and the languages"
        else "$CLEAR_TITLE, unavailable, there is nothing to clear"

    const val WEBSITE_ACCESSIBILITY = "Visit zetic.ai, opens in the browser"
    const val CONTACT_ACCESSIBILITY = "Contact us, copies $CONTACT_EMAIL to the clipboard"
}

/**
 * The drawer panel's content. Row labels are terse and left-aligned; each row's trailing glyph is
 * a quiet [TextSecondary] icon that repeats what the label already says.
 *
 * The `App language` and `Storage` rows the shared spec describes are not here yet: localization is
 * a later stage, and the storage row needs a read-only answer about the Melange cache that the
 * Android SDK does not offer today. The row list is the extension point for both.
 */
@Composable
fun SettingsDrawerContent(
    appInfo: AppInfo,
    canClearConversation: Boolean,
    onClearConversation: () -> Unit,
    onVisitWebsite: () -> Unit,
    onCopyContact: () -> Unit,
    onClose: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        Row(
            Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 16.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                SettingsDrawerCopy.TITLE,
                color = TextPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            Icon(
                Icons.Filled.Close,
                contentDescription = SettingsDrawerCopy.CLOSE,
                tint = TextSecondary,
                modifier = Modifier
                    .clickable(onClick = onClose)
                    .padding(8.dp)
                    .size(20.dp),
            )
        }
        HorizontalDivider(color = DividerLine)

        SettingsRow(
            title = SettingsDrawerCopy.CLEAR_TITLE,
            subtitle = SettingsDrawerCopy.CLEAR_SUBTITLE,
            accessibilityLabel = SettingsDrawerCopy.clearAccessibilityLabel(canClearConversation),
            icon = Icons.Filled.Delete,
            enabled = canClearConversation,
            onClick = onClearConversation,
        )
        HorizontalDivider(color = DividerLine)

        SettingsRow(
            title = SettingsDrawerCopy.WEBSITE_TITLE,
            subtitle = null,
            accessibilityLabel = SettingsDrawerCopy.WEBSITE_ACCESSIBILITY,
            painter = painterResource(R.drawable.ic_open_in_new),
            enabled = true,
            onClick = onVisitWebsite,
        )
        HorizontalDivider(color = DividerLine)

        SettingsRow(
            title = SettingsDrawerCopy.CONTACT_TITLE,
            subtitle = SettingsDrawerCopy.CONTACT_EMAIL,
            accessibilityLabel = SettingsDrawerCopy.CONTACT_ACCESSIBILITY,
            painter = painterResource(R.drawable.ic_copy),
            enabled = true,
            onClick = onCopyContact,
        )
        HorizontalDivider(color = DividerLine)

        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(SettingsDrawerCopy.ABOUT_TITLE, color = TextSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text(appInfo.displayName, color = TextPrimary, fontSize = 16.sp)
            Text(appInfo.versionLine, color = TextSecondary, fontSize = 12.sp)
            Text(SettingsDrawerCopy.PRIVACY_LINE, color = TextSecondary, fontSize = 12.sp)
        }
    }
}

@Composable
private fun SettingsRow(
    title: String,
    subtitle: String?,
    accessibilityLabel: String,
    enabled: Boolean,
    onClick: () -> Unit,
    icon: ImageVector? = null,
    painter: Painter? = null,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .semantics(mergeDescendants = true) {
                contentDescription = accessibilityLabel
                role = Role.Button
                if (!enabled) disabled()
            }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = if (enabled) TextPrimary else TextSecondary, fontSize = 16.sp)
            subtitle?.let { Text(it, color = TextSecondary, fontSize = 12.sp) }
        }
        // The glyph repeats what the label already says, so it is hidden from the reader rather
        // than announced a second time inside the row's merged description.
        val glyph = Modifier.size(20.dp).clearAndSetSemantics { }
        when {
            painter != null -> Icon(painter, contentDescription = null, tint = TextSecondary, modifier = glyph)
            icon != null -> Icon(icon, contentDescription = null, tint = TextSecondary, modifier = glyph)
        }
    }
}
