package ai.zetic.realtimetranslate

import android.content.Context
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContent
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

sealed interface UiAction {
    data object RequestPermission : UiAction
    data class SelectInput(val speaker: Speaker, val language: SpeechLanguage) : UiAction
    data class SelectReading(val speaker: Speaker, val language: TranslationLanguage) : UiAction
    data object StartConversation : UiAction
    data object EndSession : UiAction
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
    is UiAction.PttPress -> SessionAction.PttPress(context, speaker)
    is UiAction.PttRelease -> SessionAction.PttRelease(speaker)
    is UiAction.TogglePtt -> SessionAction.TogglePtt(context, speaker)
    UiAction.Retry -> SessionAction.Retry
}

private val MessageShape: Shape = RoundedCornerShape(16.dp)
private val ControlShape: Shape = RoundedCornerShape(20.dp)

fun statusLabel(state: SessionUiState): String = when (state.phase) {
    SessionPhase.PermissionRequired -> "Microphone permission required"
    SessionPhase.LoadingModel -> "Preparing translation model"
    SessionPhase.EndingSession -> "Ending session"
    SessionPhase.ModelLoadFailed -> "Translation model unavailable"
    SessionPhase.Ready -> if (state.conversationStarted) "Conversation ready" else "Ready to start"
    SessionPhase.ListeningA -> "Speaker A is speaking"
    SessionPhase.ListeningB -> "Speaker B is speaking"
    SessionPhase.FinalizingA -> "Finalizing speaker A transcript"
    SessionPhase.FinalizingB -> "Finalizing speaker B transcript"
    SessionPhase.TranslatingA -> "Translating for speaker B"
    SessionPhase.TranslatingB -> "Translating for speaker A"
    SessionPhase.Error -> "An error occurred"
}

/**
 * One screen holds everything: title and status, an inline session banner, the chat transcript,
 * per-speaker language chips, and the A/B push-to-talk controls.
 */
@Composable
fun RealtimeTranslateApp(state: SessionUiState, onAction: (UiAction) -> Unit, onOpenAppSettings: () -> Unit = {}) {
    Column(
        Modifier.fillMaxSize().background(Surface).windowInsetsPadding(WindowInsets.safeContent),
    ) {
        Header(state)
        SessionBanner(state, onAction, onOpenAppSettings)
        ConversationList(state, Modifier.weight(1f))
        BottomBar(state, onAction)
    }
}

@Composable private fun Header(state: SessionUiState) {
    val status = statusLabel(state)
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text("Turn Translate", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
        Text(
            status,
            color = TextSecondary,
            fontSize = 12.sp,
            modifier = Modifier.semantics { contentDescription = "Session status: $status" },
        )
        if (state.speechLanguageCatalogLoading) {
            Text("Checking installed on-device languages", color = TextSecondary, fontSize = 12.sp)
        }
        state.speechLanguageCatalogMessage?.let { Text(it, color = TextSecondary, fontSize = 12.sp) }
    }
    HorizontalDivider(color = DividerLine)
}

@Composable private fun SessionBanner(state: SessionUiState, onAction: (UiAction) -> Unit, onOpenAppSettings: () -> Unit) {
    when (state.phase) {
        SessionPhase.PermissionRequired -> Banner {
            Text("Turn Translate needs microphone access to recognize speech on this device.", color = TextPrimary, fontSize = 14.sp)
            if (state.permissionPermanentlyDenied) {
                BannerAction("Open app settings", "Open app settings", onOpenAppSettings)
            } else {
                BannerAction("Allow microphone", "Request microphone permission") { onAction(UiAction.RequestPermission) }
            }
        }
        SessionPhase.LoadingModel -> Banner {
            Text("Loading translation model ${(state.modelLoadProgress * 100).toInt()}%", color = TextPrimary, fontSize = 14.sp)
            LinearProgressIndicator(
                progress = { state.modelLoadProgress },
                modifier = Modifier.fillMaxWidth(),
                color = Accent,
                trackColor = DividerLine,
            )
            Text("Speaker controls unlock when the model is ready.", color = TextSecondary, fontSize = 12.sp)
        }
        SessionPhase.ModelLoadFailed -> Banner {
            Text(state.errorMessage ?: "The translation model could not be loaded.", color = Error, fontSize = 14.sp)
            BannerAction("Retry model load", "Retry model load") { onAction(UiAction.Retry) }
        }
        SessionPhase.EndingSession -> Banner {
            Text("Unloading translation model", color = TextSecondary, fontSize = 14.sp)
        }
        SessionPhase.Error -> Banner {
            Text(state.errorMessage.orEmpty(), color = Error, fontSize = 14.sp)
            BannerAction("Try again", "Try again") { onAction(UiAction.Retry) }
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

@Composable private fun ConversationList(state: SessionUiState, modifier: Modifier) {
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
                val hint = if (state.conversationStarted) {
                    "Speaker A or B can begin speaking."
                } else {
                    "Choose the languages below, then start the session."
                }
                Text(hint, color = TextSecondary, fontSize = 14.sp)
            }
        }
        items(state.conversations, key = { it.id }) { MessageBubble(it) }
    }
}

@Composable private fun MessageBubble(item: ConversationItem) {
    val isA = item.speaker == Speaker.A
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (isA) Arrangement.Start else Arrangement.End,
    ) {
        val bubble = if (isA) {
            Modifier.clip(MessageShape).background(SurfaceSubtle)
        } else {
            Modifier.clip(MessageShape).background(Surface).border(1.dp, DividerLine, MessageShape)
        }
        Column(
            Modifier
                .fillMaxWidth(0.88f)
                .then(bubble)
                .padding(12.dp)
                .semantics { contentDescription = "Speaker ${item.speaker.label} utterance" },
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                "Speaker ${item.speaker.label}",
                color = TextSecondary,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(item.transcript, fontSize = 16.sp, color = TextPrimary)
            HorizontalDivider(color = DividerLine)
            Text("To ${item.speaker.other().label} - ${item.targetLanguage.displayName}", color = TextSecondary, fontSize = 12.sp)
            when {
                item.translation != null -> Text(item.translation, fontSize = 16.sp, color = TextPrimary, fontWeight = FontWeight.Medium)
                item.translationError != null -> Text(item.translationError, color = Error, fontSize = 12.sp)
                item.isFinal -> Text("Translation pending", color = TextSecondary, fontSize = 12.sp)
                else -> Text("Recognizing speech", color = TextSecondary, fontSize = 12.sp)
            }
        }
    }
}

@Composable private fun BottomBar(state: SessionUiState, onAction: (UiAction) -> Unit) {
    HorizontalDivider(color = DividerLine)
    Column(
        Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SpeakerColumn(Speaker.A, state, onAction, Modifier.weight(1f))
            SpeakerColumn(Speaker.B, state, onAction, Modifier.weight(1f))
        }
        Text(bottomHint(state), color = TextSecondary, fontSize = 12.sp)
        SessionButton(state, onAction)
    }
}

private fun bottomHint(state: SessionUiState): String {
    val active = state.activeSpeaker()
    return when {
        state.phase == SessionPhase.PermissionRequired -> "Grant microphone access to enable push-to-talk."
        !state.conversationStarted -> "Push-to-talk unlocks once the translation model is ready."
        active != null -> "Speaker ${active.other().label} cannot begin while speaker ${active.label} is active."
        else -> "Hold a button to talk, or tap once to start and again to stop."
    }
}

/** Language chips can be changed at any time except while an utterance is in flight. */
private fun canEditLanguages(state: SessionUiState): Boolean =
    state.activeSpeaker() == null &&
        state.phase != SessionPhase.LoadingModel &&
        state.phase != SessionPhase.EndingSession

@Composable private fun SpeakerColumn(speaker: Speaker, state: SessionUiState, onAction: (UiAction) -> Unit, modifier: Modifier) {
    val settings = state.settingsFor(speaker)
    val enabled = canEditLanguages(state)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            speaker.label,
            color = TextSecondary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.semantics { contentDescription = "Speaker ${speaker.label} controls" },
        )
        LanguageChip(
            label = "Speaker ${speaker.label} recognition language",
            caption = "Speaks",
            selected = settings.inputLanguage.displayName,
            options = state.speechLanguages.map { it.displayName to UiAction.SelectInput(speaker, it) },
            enabled = enabled,
            onAction = onAction,
        )
        LanguageChip(
            label = "Speaker ${speaker.label} translation language",
            caption = "Reads",
            selected = settings.readingLanguage.displayName,
            options = HyMt2Languages.all.map { it.displayName to UiAction.SelectReading(speaker, it) },
            enabled = enabled,
            onAction = onAction,
        )
        PttControl(speaker, state, onAction, Modifier.fillMaxWidth())
    }
}

@Composable private fun LanguageChip(
    label: String,
    caption: String,
    selected: String,
    options: List<Pair<String, UiAction>>,
    enabled: Boolean,
    onAction: (UiAction) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(
            onClick = { expanded = true },
            enabled = enabled,
            shape = ControlShape,
            border = BorderStroke(1.dp, DividerLine),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Surface, contentColor = TextPrimary),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "$label selector: $selected" },
        ) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(caption, color = TextSecondary, fontSize = 12.sp)
                Text(selected, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, modifier = Modifier.heightIn(max = 320.dp)) {
            options.forEach { (name, action) ->
                DropdownMenuItem(text = { Text(name) }, onClick = { expanded = false; onAction(action) })
            }
        }
    }
}

@Composable private fun PttControl(speaker: Speaker, state: SessionUiState, onAction: (UiAction) -> Unit, modifier: Modifier) {
    val active = state.activeSpeaker()
    val listening = state.phase == if (speaker == Speaker.A) SessionPhase.ListeningA else SessionPhase.ListeningB
    val enabled = state.conversationStarted && (state.phase == SessionPhase.Ready || listening)
    val actionLabel = if (listening) "Stop speaker ${speaker.label}" else "Start speaker ${speaker.label}"
    val blockedLabel = if (active != null) {
        "Speaker ${speaker.label} cannot start while speaker ${active.label} is active"
    } else {
        "Speaker ${speaker.label} push-to-talk unlocks when the translation model is ready"
    }
    val container = when {
        listening -> Accent
        enabled -> Surface
        else -> SurfaceSubtle
    }
    val contentColor = when {
        listening -> Surface
        enabled -> TextPrimary
        else -> TextSecondary
    }
    Box(
        modifier
            .clip(ControlShape)
            .background(container)
            .border(1.dp, if (listening) Accent else DividerLine, ControlShape)
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
            if (listening) "${speaker.label} recording - release to stop" else "${speaker.label} - hold to talk",
            color = contentColor,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable private fun SessionButton(state: SessionUiState, onAction: (UiAction) -> Unit) {
    if (state.conversationStarted) {
        OutlinedButton(
            onClick = { onAction(UiAction.EndSession) },
            enabled = state.phase != SessionPhase.EndingSession,
            shape = ControlShape,
            border = BorderStroke(1.dp, DividerLine),
            colors = ButtonDefaults.outlinedButtonColors(containerColor = Surface, contentColor = TextPrimary),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "End session" },
        ) { Text("End session", fontSize = 14.sp) }
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
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Start conversation" },
        ) { Text("Start conversation", fontSize = 14.sp) }
    }
}
