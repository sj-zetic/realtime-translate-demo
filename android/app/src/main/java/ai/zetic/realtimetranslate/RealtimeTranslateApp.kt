package ai.zetic.realtimetranslate

import android.content.Context
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContent
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

sealed interface UiAction {
    data object RequestPermission : UiAction
    data class SelectInput(val speaker: Speaker, val language: SpeechLanguage) : UiAction
    data class SelectReading(val speaker: Speaker, val language: TranslationLanguage) : UiAction
    data object StartConversation : UiAction
    data object EndSession : UiAction
    data object ClearConversation : UiAction
    data class PttPress(val speaker: Speaker) : UiAction
    data class PttRelease(val speaker: Speaker) : UiAction
    data class TogglePtt(val speaker: Speaker) : UiAction
    data object Retry : UiAction
}

fun UiAction.toSessionAction(context: Context): SessionAction = when (this) {
    UiAction.RequestPermission -> SessionAction.Retry
    is UiAction.SelectInput -> SessionAction.InputLanguageChanged(speaker, language)
    is UiAction.SelectReading -> SessionAction.ReadingLanguageChanged(speaker, language)
    UiAction.StartConversation -> SessionAction.StartConversation(context)
    UiAction.EndSession -> SessionAction.EndSession
    UiAction.ClearConversation -> SessionAction.ClearConversation
    is UiAction.PttPress -> SessionAction.PttPress(context, speaker)
    is UiAction.PttRelease -> SessionAction.PttRelease(speaker)
    is UiAction.TogglePtt -> SessionAction.TogglePtt(context, speaker)
    UiAction.Retry -> SessionAction.Retry
}

fun statusLabel(state: SessionUiState): UiText = when (state.phase) {
    SessionPhase.PermissionRequired -> UiText.res(R.string.status_permission_required)
    SessionPhase.LoadingModel -> UiText.res(R.string.status_preparing_model)
    SessionPhase.ModelLoadFailed -> UiText.res(R.string.status_model_unavailable)
    SessionPhase.Ready ->
        if (state.conversationStarted) UiText.res(R.string.status_conversation_ready) else UiText.res(R.string.status_ready_to_start)
    SessionPhase.ListeningA -> UiText.res(R.string.status_listening, Speaker.A.label)
    SessionPhase.ListeningB -> UiText.res(R.string.status_listening, Speaker.B.label)
    SessionPhase.FinalizingA -> UiText.res(R.string.status_finalizing, Speaker.A.label)
    SessionPhase.FinalizingB -> UiText.res(R.string.status_finalizing, Speaker.B.label)
    // The status names who the translation is *for*, which is the other speaker.
    SessionPhase.TranslatingA -> UiText.res(R.string.status_translating, Speaker.B.label)
    SessionPhase.TranslatingB -> UiText.res(R.string.status_translating, Speaker.A.label)
    SessionPhase.Error -> UiText.res(R.string.status_error)
}

/**
 * One screen holds everything: title and status, a per-speaker language bar, an inline session
 * banner, the chat transcript, and the A/B push-to-talk controls.
 */
@Composable
fun RealtimeTranslateApp(
    state: SessionUiState,
    onAction: (UiAction) -> Unit,
    onOpenAppSettings: () -> Unit = {},
    onOpenSettingsDrawer: () -> Unit = {},
    onCopyBubble: (ConversationItem) -> Unit = {},
    copyToast: ToastState? = null,
    isMuted: Boolean = false,
    onToggleMute: () -> Unit = {},
    onReplayBubble: (ConversationItem) -> Unit = {},
) {
    Column(
        Modifier.fillMaxSize().background(Surface).windowInsetsPadding(WindowInsets.safeContent),
    ) {
        Header(state, onOpenSettingsDrawer, isMuted, onToggleMute)
        LanguageBar(state, onAction)
        SessionBanner(state, onAction, onOpenAppSettings)
        // The copy confirmation is anchored to the bottom of the transcript rather than the bottom
        // of the screen, so it never lands on top of the push-to-talk row or the session action.
        Box(Modifier.weight(1f)) {
            ConversationList(state, Modifier.fillMaxSize(), onCopyBubble, isMuted, onReplayBubble)
            copyToast?.let { ToastHost(it, Modifier.align(Alignment.BottomCenter)) }
        }
        BottomBar(state, onAction)
    }
}

@Composable private fun Header(
    state: SessionUiState,
    onOpenSettingsDrawer: () -> Unit,
    isMuted: Boolean,
    onToggleMute: () -> Unit,
) {
    val status = statusLabel(state).text()
    val statusAccessibility = stringResource(R.string.status_accessibility, status)
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                FirstRunCopy.PRODUCT_NAME,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                modifier = Modifier.weight(1f),
            )
            ZeticWordmarkButton(onOpenSettingsDrawer)
        }
        // The status strip is one short line with its whole trailing half empty, so the app's only
        // always-present control lands there without crowding the header or adding a row of chrome.
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                status,
                color = TextSecondary,
                fontSize = 12.sp,
                modifier = Modifier
                    .weight(1f)
                    .semantics { contentDescription = statusAccessibility },
            )
            SoundToggle(isMuted, onToggleMute)
        }
        if (state.speechLanguageCatalogLoading) {
            Text(stringResource(R.string.speech_catalog_loading), color = TextSecondary, fontSize = 12.sp)
        }
        state.speechLanguageCatalogMessage?.let { Text(it.text(), color = TextSecondary, fontSize = 12.sp) }
    }
    HorizontalDivider(color = DividerLine)
}

/**
 * The one sound control: a speaker glyph when sound is on, a crossed-out speaker when it is off.
 * The glyph is its whole face, so the state is announced in words rather than left to the icon.
 */
@Composable private fun SoundToggle(isMuted: Boolean, onToggle: () -> Unit) {
    // The label is the state in words, so the control needs no separate state description: an
    // Android switch would announce its own `on` after a label that already said which it is.
    val label = stringResource(if (isMuted) R.string.sound_off_label else R.string.sound_on_label)
    IconButton(
        onClick = onToggle,
        modifier = Modifier.size(28.dp).semantics(mergeDescendants = true) {
            contentDescription = label
            role = Role.Button
        },
    ) {
        Icon(
            painterResource(if (isMuted) R.drawable.ic_volume_off else R.drawable.ic_volume_up),
            contentDescription = null,
            tint = if (isMuted) TextSecondary else Accent,
            modifier = Modifier.size(18.dp),
        )
    }
}

/**
 * The official ZETIC logo lockup, from `res/drawable-nodpi/zetic_logo.png`, as the control that
 * opens the settings drawer. The chevron is the only affordance that says the lockup is tappable.
 */
@Composable private fun ZeticWordmarkButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .clip(ControlShape)
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) {
                contentDescription = "ZETIC, opens settings"
                role = Role.Button
            }
            .padding(horizontal = 6.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Image(
            painterResource(R.drawable.zetic_logo),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier.height(16.dp),
        )
        Icon(
            Icons.Filled.KeyboardArrowDown,
            contentDescription = null,
            tint = TextSecondary,
            modifier = Modifier.size(14.dp),
        )
    }
}

/** Language chips can be changed at any time except while an utterance is in flight. */
private fun canEditLanguages(state: SessionUiState): Boolean =
    state.activeSpeaker() == null && state.phase != SessionPhase.LoadingModel

/**
 * Chips render the short form; the menu entries keep the full display name. `Automatic` loses its
 * parenthetical here rather than gaining a second catalog entry, so the two can never drift.
 */
@Composable private fun shortLanguageName(language: SpeechLanguage): String = when (language) {
    SpeechLanguage.Automatic -> stringResource(R.string.speech_language_automatic).substringBefore(" (")
    is SpeechLanguage.Installed -> language.name
}

/** One chip per speaker, mirroring the side their chat bubbles appear on. */
@Composable private fun LanguageBar(state: SessionUiState, onAction: (UiAction) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SpeakerLanguageChip(Speaker.A, state, onAction, Modifier.weight(1f, fill = false))
        SpeakerLanguageChip(Speaker.B, state, onAction, Modifier.weight(1f, fill = false))
    }
    HorizontalDivider(color = DividerLine)
}

@Composable private fun SpeakerLanguageChip(
    speaker: Speaker,
    state: SessionUiState,
    onAction: (UiAction) -> Unit,
    modifier: Modifier,
) {
    val settings = state.settingsFor(speaker)
    val enabled = canEditLanguages(state)
    val reading = settings.readingLanguage.displayName
    val speaking = shortLanguageName(settings.inputLanguage)
    val chipAccessibility = stringResource(R.string.language_chip_accessibility, speaker.label, reading, speaking)
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        OutlinedButton(
            onClick = { expanded = true },
            enabled = enabled,
            shape = ControlShape,
            border = BorderStroke(1.dp, if (enabled) speakerBorder(speaker) else DividerLine),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Surface, contentColor = TextPrimary),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
            modifier = Modifier.semantics { contentDescription = chipAccessibility },
        ) {
            Text(
                buildAnnotatedString {
                    withStyle(
                        SpanStyle(
                            color = if (enabled) speakerDeep(speaker) else TextSecondary,
                            fontWeight = FontWeight.Bold,
                        ),
                    ) { append("${speaker.label} ·") }
                    append(" ")
                    append(reading)
                },
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, modifier = Modifier.heightIn(max = 360.dp)) {
            MenuSectionHeader(stringResource(R.string.menu_reading_language))
            HyMt2Languages.all.forEach { language ->
                DropdownMenuItem(
                    text = { Text(language.displayName) },
                    onClick = { expanded = false; onAction(UiAction.SelectReading(speaker, language)) },
                )
            }
            HorizontalDivider(color = DividerLine)
            MenuSectionHeader(stringResource(R.string.menu_spoken_language))
            state.speechLanguages.forEach { language ->
                DropdownMenuItem(
                    text = { Text(language.displayName.text()) },
                    onClick = { expanded = false; onAction(UiAction.SelectInput(speaker, language)) },
                )
            }
        }
    }
}

@Composable private fun MenuSectionHeader(label: String) {
    Text(
        label,
        color = TextSecondary,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

@Composable private fun SessionBanner(state: SessionUiState, onAction: (UiAction) -> Unit, onOpenAppSettings: () -> Unit) {
    when (state.phase) {
        SessionPhase.PermissionRequired -> Banner {
            Text(stringResource(R.string.banner_permission_body), color = TextPrimary, fontSize = 14.sp)
            if (state.permissionPermanentlyDenied) {
                val open = stringResource(R.string.banner_open_app_settings)
                BannerAction(open, open, onOpenAppSettings)
            } else {
                BannerAction(
                    stringResource(R.string.banner_allow_microphone),
                    stringResource(R.string.banner_request_permission_accessibility),
                ) { onAction(UiAction.RequestPermission) }
            }
        }
        SessionPhase.LoadingModel -> Banner {
            Text(
                stringResource(R.string.banner_loading_model, (state.modelLoadProgress * 100).toInt()),
                color = TextPrimary,
                fontSize = 14.sp,
            )
            LinearProgressIndicator(
                progress = { state.modelLoadProgress },
                modifier = Modifier.fillMaxWidth(),
                color = Accent,
                trackColor = DividerLine,
            )
            Text(stringResource(R.string.banner_controls_unlock), color = TextSecondary, fontSize = 12.sp)
        }
        SessionPhase.ModelLoadFailed -> Banner {
            Text(
                state.errorMessage?.text() ?: stringResource(R.string.error_model_load_failed),
                color = Error,
                fontSize = 14.sp,
            )
            val retry = stringResource(R.string.banner_retry_model_load)
            BannerAction(retry, retry) { onAction(UiAction.Retry) }
        }
        SessionPhase.Error -> Banner {
            Text(state.errorMessage?.text().orEmpty(), color = Error, fontSize = 14.sp)
            val tryAgain = stringResource(R.string.banner_try_again)
            BannerAction(tryAgain, tryAgain) { onAction(UiAction.Retry) }
        }
        else -> Unit
    }
}

@Composable private fun Banner(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().background(SurfaceSubtle).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
    HorizontalDivider(color = DividerLine)
}

@Composable private fun BannerAction(label: String, description: String, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        shape = ControlShape,
        border = BorderStroke(1.dp, DividerLine),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = Surface, contentColor = TextPrimary),
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = description },
    ) { Text(label, fontSize = 14.sp) }
}

@Composable private fun ConversationList(
    state: SessionUiState,
    modifier: Modifier,
    onCopyBubble: (ConversationItem) -> Unit,
    isMuted: Boolean,
    onReplayBubble: (ConversationItem) -> Unit,
) {
    val listState = rememberLazyListState()
    LaunchedEffect(state.conversations.size) {
        if (state.conversations.isNotEmpty()) listState.animateScrollToItem(state.conversations.lastIndex)
    }
    LazyColumn(
        modifier.fillMaxWidth(),
        state = listState,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(16.dp),
    ) {
        if (state.conversations.isEmpty()) {
            item {
                val hint = stringResource(
                    if (state.conversationStarted) R.string.transcript_empty_live else R.string.transcript_empty_idle,
                )
                Text(hint, color = TextSecondary, fontSize = 14.sp)
            }
        }
        items(state.conversations, key = { it.id }) {
            MessageBubble(it, onCopyBubble, isMuted, state.isRecognizerLive, onReplayBubble)
        }
    }
}

/**
 * A named menu action rather than a bare long press that copies silently: the transcript scrolls,
 * so a bare gesture fires on a slow drag, and the menu names the action before it happens and
 * exposes it to the accessibility service. A bubble with nothing to copy offers no action at all.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable private fun MessageBubble(
    item: ConversationItem,
    onCopyBubble: (ConversationItem) -> Unit,
    isMuted: Boolean,
    isRecognizerLive: Boolean,
    onReplayBubble: (ConversationItem) -> Unit,
) {
    val isA = item.speaker == Speaker.A
    var menuExpanded by remember { mutableStateOf(false) }
    val copyable = item.copyableText != null
    val copyAction = stringResource(R.string.bubble_copy_action)
    val bubbleAccessibility = stringResource(R.string.bubble_accessibility, item.speaker.label)
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (isA) Arrangement.Start else Arrangement.End,
    ) {
        Column(
            Modifier
                .fillMaxWidth(0.88f)
                .clip(MessageShape)
                .background(speakerTint(item.speaker))
                .combinedClickable(
                    enabled = copyable,
                    onClick = {},
                    onLongClick = { menuExpanded = true },
                    onLongClickLabel = copyAction,
                )
                .padding(12.dp)
                .semantics { contentDescription = bubbleAccessibility },
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                DropdownMenuItem(
                    text = { Text(copyAction) },
                    onClick = { menuExpanded = false; onCopyBubble(item) },
                )
            }
            Text(
                stringResource(R.string.bubble_speaker_heading, item.speaker.label),
                color = speakerDeep(item.speaker),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(item.transcript, fontSize = 16.sp, color = TextPrimary)
            HorizontalDivider(color = DividerLine)
            Text(
                stringResource(R.string.bubble_destination, item.speaker.other().label, item.targetLanguage.displayName),
                color = TextSecondary,
                fontSize = 12.sp,
            )
            // The replay control sits in the bottom trailing corner of the translation region, as a
            // separate element from the bubble, so the bubble's own label and its copy long press
            // are unchanged.
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Box(Modifier.weight(1f)) {
                    when {
                        item.translation != null ->
                            Text(item.translation, fontSize = 16.sp, color = TextPrimary, fontWeight = FontWeight.Medium)
                        item.translationError != null -> Text(item.translationError.text(), color = Error, fontSize = 12.sp)
                        item.isFinal -> Text(stringResource(R.string.bubble_translation_pending), color = TextSecondary, fontSize = 12.sp)
                        else -> Text(stringResource(R.string.bubble_recognizing), color = TextSecondary, fontSize = 12.sp)
                    }
                }
                if (ReplayControl.isPresent(item)) {
                    ReplayButton(
                        enabled = ReplayControl.isEnabled(item, isMuted, isRecognizerLive),
                        onClick = { onReplayBubble(item) },
                    )
                }
            }
        }
    }
}

/** Absent, not disabled, on a bubble with nothing to play; disabled while nothing can be heard. */
@Composable private fun ReplayButton(enabled: Boolean, onClick: () -> Unit) {
    val label = stringResource(R.string.replay_label)
    val hint = stringResource(R.string.replay_hint)
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(28.dp).semantics(mergeDescendants = true) {
            contentDescription = label
            // Compose has no hint slot, so the sentence that says what the tap will do rides on the
            // click label the accessibility service reads out with the action.
            onClick(label = hint) { onClick(); true }
            role = Role.Button
            if (!enabled) disabled()
        },
    ) {
        Icon(
            painterResource(R.drawable.ic_volume_up),
            contentDescription = null,
            tint = if (enabled) speakerDeep(Speaker.A) else TextSecondary,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable private fun BottomBar(state: SessionUiState, onAction: (UiAction) -> Unit) {
    HorizontalDivider(color = DividerLine)
    Column(
        Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PttControl(Speaker.A, state, onAction, Modifier.weight(1f))
            PttControl(Speaker.B, state, onAction, Modifier.weight(1f))
        }
        Text(bottomHint(state).text(), color = TextSecondary, fontSize = 12.sp)
        SessionButton(state, onAction)
    }
}

private fun bottomHint(state: SessionUiState): UiText {
    val active = state.activeSpeaker()
    return when {
        state.phase == SessionPhase.PermissionRequired -> UiText.res(R.string.hint_grant_microphone)
        state.phase == SessionPhase.LoadingModel || state.phase == SessionPhase.ModelLoadFailed ->
            UiText.res(R.string.hint_model_not_ready)
        state.phase == SessionPhase.Error -> UiText.res(R.string.hint_resolve_error)
        !state.conversationStarted -> UiText.res(R.string.hint_start_conversation)
        active != null -> UiText.res(R.string.hint_other_speaker_active, active.other().label, active.label)
        else -> UiText.res(R.string.hint_push_to_talk)
    }
}

@Composable private fun PttControl(speaker: Speaker, state: SessionUiState, onAction: (UiAction) -> Unit, modifier: Modifier) {
    val active = state.activeSpeaker()
    val listening = state.phase == if (speaker == Speaker.A) SessionPhase.ListeningA else SessionPhase.ListeningB
    val enabled = state.conversationStarted && (state.phase == SessionPhase.Ready || listening)
    val actionLabel = stringResource(if (listening) R.string.ptt_stop else R.string.ptt_start, speaker.label)
    val blockedLabel = if (active != null) {
        stringResource(R.string.ptt_blocked_by_other, speaker.label, active.label)
    } else {
        stringResource(R.string.ptt_blocked_model_not_ready, speaker.label)
    }
    val container = when {
        listening -> speakerAccent(speaker)
        enabled -> Surface
        else -> SurfaceSubtle
    }
    val contentColor = when {
        listening -> Surface
        enabled -> TextPrimary
        else -> TextSecondary
    }
    val prefixColor = when {
        listening -> Surface
        enabled -> speakerDeep(speaker)
        else -> TextSecondary
    }
    val borderColor = when {
        listening -> speakerAccent(speaker)
        enabled -> speakerBorder(speaker)
        else -> DividerLine
    }
    val caption = stringResource(if (listening) R.string.ptt_caption_recording else R.string.ptt_caption_idle)
    val label = buildAnnotatedString {
        withStyle(SpanStyle(color = prefixColor, fontWeight = FontWeight.Bold)) { append(speaker.label) }
        append(caption)
    }
    Box(
        modifier
            .clip(ControlShape)
            .background(container)
            .border(1.dp, borderColor, ControlShape)
            .semantics(mergeDescendants = true) {
                contentDescription = if (enabled) actionLabel else blockedLabel
                if (enabled) onClick { onAction(UiAction.TogglePtt(speaker)); true } else disabled()
            }
            .pointerInput(enabled, listening) {
                if (enabled) {
                    detectTapGestures(
                        onPress = {
                            onAction(UiAction.PttPress(speaker))
                            tryAwaitRelease()
                            onAction(UiAction.PttRelease(speaker))
                        },
                    )
                }
            }
            .padding(vertical = 16.dp, horizontal = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = contentColor,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable private fun SessionButton(state: SessionUiState, onAction: (UiAction) -> Unit) {
    val endLabel = stringResource(R.string.session_end)
    val startLabel = stringResource(R.string.session_start)
    if (state.conversationStarted) {
        OutlinedButton(
            onClick = { onAction(UiAction.EndSession) },
            shape = ControlShape,
            border = BorderStroke(1.dp, DividerLine),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Surface, contentColor = TextPrimary),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = endLabel },
        ) { Text(endLabel, fontSize = 14.sp) }
    } else {
        Button(
            onClick = { onAction(UiAction.StartConversation) },
            enabled = state.phase == SessionPhase.Ready,
            shape = ControlShape,
            colors = ButtonDefaults.buttonColors(
                containerColor = Accent,
                contentColor = Surface,
                disabledContainerColor = SurfaceSubtle,
                disabledContentColor = TextSecondary,
            ),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = startLabel },
        ) { Text(startLabel, fontSize = 14.sp) }
    }
}
