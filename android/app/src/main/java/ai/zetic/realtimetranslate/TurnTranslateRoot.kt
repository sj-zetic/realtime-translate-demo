package ai.zetic.realtimetranslate

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContent
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import kotlinx.coroutines.launch

/**
 * Everything that wraps around the single main screen: the settings drawer, the three first-run
 * surfaces, and the session-comfort behaviors. The main screen itself is composed unchanged inside,
 * so opening the drawer or answering a first-run step never rebuilds it and never touches the
 * Melange session the view model owns.
 *
 * @param isMetered read at the moment consent is decided rather than observed, because the answer
 * only matters for the one frame the card is built in.
 */
@Composable
fun TurnTranslateRoot(
    state: SessionUiState,
    onAction: (UiAction) -> Unit,
    onOpenAppSettings: () -> Unit,
    onVisitWebsite: () -> Unit,
    preferences: FirstRunPreferences,
    appInfo: AppInfo,
    isMetered: () -> Boolean,
    hasPersonalKey: Boolean,
) {
    val scope = rememberCoroutineScope()
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val drawerToast = rememberToastState()
    val copyToast = rememberToastState()
    val clipboard = LocalClipboardManager.current
    val haptics = rememberHapticPlayer()

    var welcomeSeen by remember { mutableStateOf(preferences.welcomeSeen) }
    var primingSeen by remember { mutableStateOf(preferences.permissionPrimingSeen) }
    var consent by remember { mutableStateOf<ConsentPrompt?>(null) }
    var pendingStart by remember { mutableStateOf<UiAction?>(null) }

    KeepScreenAwake(state)
    ComfortHaptics(state, haptics)

    // The one honest signal this build has that a model is already on the phone. Written the first
    // time a load succeeds, so the second session never asks for consent to a download that is not
    // going to happen.
    LaunchedEffect(state.conversationStarted) {
        if (state.conversationStarted) preferences.hasEverLoadedModel = true
    }

    /** Every path that would load the model routes through the consent gate, retry included. */
    fun requestSessionStart(action: UiAction) {
        when (
            val decision = ModelDownloadConsent.decision(
                hasLocalModel = preferences.hasEverLoadedModel,
                isMetered = isMetered(),
                hasPersonalKey = hasPersonalKey,
            )
        ) {
            ModelDownloadConsent.Decision.StartImmediately -> onAction(action)
            is ModelDownloadConsent.Decision.Ask -> {
                pendingStart = action
                consent = ConsentPrompt(decision.cellularWarning)
            }
        }
    }

    fun handle(action: UiAction) {
        when {
            action == UiAction.StartConversation -> requestSessionStart(action)
            action == UiAction.Retry && state.phase == SessionPhase.ModelLoadFailed -> requestSessionStart(action)
            else -> {
                // The control is only enabled when a turn can actually start, so the press is the
                // moment worth confirming by feel rather than the recognizer's later callback.
                when (action) {
                    is UiAction.PttPress -> haptics(HapticEvent.TurnBegan)
                    is UiAction.PttRelease -> haptics(HapticEvent.TurnEnded)
                    else -> Unit
                }
                onAction(action)
            }
        }
    }

    fun copy(text: String, confirmation: String, toast: ToastState) {
        clipboard.setText(AnnotatedString(text))
        toast.show(confirmation)
    }

    Box(Modifier.fillMaxSize().background(Surface)) {
        // Material's drawer opens from the leading edge; the spec puts it on the trailing one. The
        // layout direction is flipped for the drawer scaffold alone and restored for both the sheet
        // and the main screen, so only the side and the swipe direction change.
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            ModalNavigationDrawer(
                drawerState = drawerState,
                // The wordmark is the only way in. An edge swipe on the transcript is not.
                gesturesEnabled = drawerState.isOpen,
                scrimColor = Scrim,
                drawerContent = {
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                        ModalDrawerSheet(
                            drawerShape = RectangleShape,
                            drawerContainerColor = Surface,
                            drawerContentColor = TextPrimary,
                            drawerTonalElevation = 0.dp,
                            modifier = Modifier.width(280.dp),
                        ) {
                            Row(Modifier.fillMaxHeight()) {
                                Box(Modifier.fillMaxHeight().width(1.dp).background(DividerLine))
                                SettingsDrawerContent(
                                    appInfo = appInfo,
                                    canClearConversation = state.canClearConversation,
                                    onClearConversation = {
                                        onAction(UiAction.ClearConversation)
                                        scope.launch { drawerState.close() }
                                        drawerToast.show(SettingsDrawerCopy.CLEAR_CONFIRMATION)
                                    },
                                    onVisitWebsite = onVisitWebsite,
                                    onCopyContact = {
                                        copy(SettingsDrawerCopy.CONTACT_EMAIL, SettingsDrawerCopy.COPY_CONFIRMATION, drawerToast)
                                    },
                                    onClose = { scope.launch { drawerState.close() } },
                                )
                            }
                        }
                    }
                },
            ) {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    RealtimeTranslateApp(
                        state = state,
                        onAction = ::handle,
                        onOpenAppSettings = onOpenAppSettings,
                        onOpenSettingsDrawer = { scope.launch { drawerState.open() } },
                        onCopyBubble = { item ->
                            item.copyableText?.let { copy(it, SettingsDrawerCopy.BUBBLE_COPY_CONFIRMATION, copyToast) }
                        },
                        copyToast = copyToast,
                    )
                }
            }
        }

        when (FirstRunStep.step(welcomeSeen, primingSeen, state.phase == SessionPhase.PermissionRequired)) {
            FirstRunStep.Welcome -> WelcomeSurface {
                welcomeSeen = true
                preferences.welcomeSeen = true
            }
            FirstRunStep.PermissionPriming -> PermissionPrimingSurface(
                onContinue = {
                    primingSeen = true
                    preferences.permissionPrimingSeen = true
                    onAction(UiAction.RequestPermission)
                },
                onDecline = {
                    primingSeen = true
                    preferences.permissionPrimingSeen = true
                },
            )
            FirstRunStep.None -> consent?.let { prompt ->
                ModelConsentCard(
                    prompt = prompt,
                    onDownload = {
                        val start = pendingStart
                        pendingStart = null
                        consent = null
                        start?.let(onAction)
                    },
                    // Declining remembers nothing: the next start asks again, which is also how the
                    // Wi-Fi warning gets a second chance to appear.
                    onDismiss = {
                        pendingStart = null
                        consent = null
                    },
                )
            }
        }

        ToastHost(drawerToast, Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.safeContent))
    }
}

/** What the consent card warns about. Held here so the card itself stays a pure rendering. */
data class ConsentPrompt(val cellularWarning: Boolean)

// region Session comfort shells

/**
 * Holds the display awake in exactly the states where push-to-talk is on screen, and hands it back
 * the moment the app is backgrounded or the screen goes away.
 */
@Composable
private fun KeepScreenAwake(state: SessionUiState) {
    val view = LocalView.current
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val keepAwake = ScreenAwakePolicy.shouldKeepAwake(state, lifecycleState.isAtLeast(Lifecycle.State.RESUMED))
    DisposableEffect(view, keepAwake) {
        view.keepScreenOn = keepAwake
        onDispose { view.keepScreenOn = false }
    }
}

/** Turns a [HapticEvent] into the platform feedback the phone's own haptic settings scale. */
@Composable
private fun rememberHapticPlayer(): (HapticEvent) -> Unit {
    val view = LocalView.current
    return remember(view) { { event -> view.performHapticFeedback(AndroidHaptics.constantFor(event)) } }
}

/**
 * The two haptics the session emits on its own rather than on a press: a soft tick when a
 * translation lands, and the standard rejection buzz when the error banner takes over the screen.
 * A failed translation stays silent, because the bubble already carries the failure.
 */
@Composable
private fun ComfortHaptics(state: SessionUiState, play: (HapticEvent) -> Unit) {
    val translated = remember { mutableStateOf(state.conversations.mapNotNull { it.takeIf { c -> c.translation != null }?.id }.toSet()) }
    LaunchedEffect(state.conversations) {
        val now = state.conversations.mapNotNull { it.takeIf { c -> c.translation != null }?.id }.toSet()
        if ((now - translated.value).isNotEmpty()) play(HapticEvent.TranslationDelivered)
        translated.value = now
    }
    val wasError = remember { mutableStateOf(state.phase == SessionPhase.Error) }
    LaunchedEffect(state.phase) {
        val isError = state.phase == SessionPhase.Error
        if (isError && !wasError.value) play(HapticEvent.SessionError)
        wasError.value = isError
    }
}

// endregion

// region First-run surfaces

/**
 * A full-surface step in the same minimal chrome as the app: `color.surface` fill, the ZETIC
 * lockup at the top, content leading-aligned, and the actions pinned at the bottom. It scrolls once
 * its content outgrows the phone and stays put otherwise.
 */
@Composable
private fun FirstRunSurface(content: @Composable () -> Unit, actions: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Surface)
            // Opaque and modal: taps must not reach the main screen that is still mounted behind.
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .semantics { isTraversalGroup = true; traversalIndex = -1f }
            .windowInsetsPadding(WindowInsets.safeContent)
            .padding(24.dp),
    ) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.Center) {
            content()
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) { actions() }
    }
}

@Composable
private fun WelcomeSurface(onGetStarted: () -> Unit) {
    FirstRunSurface(
        content = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                ZeticLockup()
                Text(FirstRunCopy.PRODUCT_NAME, color = TextPrimary, fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
                Text(FirstRunCopy.WELCOME_TAGLINE, color = TextPrimary, fontSize = 16.sp)
                HorizontalDivider(color = DividerLine)
                Text(FirstRunCopy.WELCOME_PRIVACY, color = TextSecondary, fontSize = 14.sp)
            }
        },
        actions = { PrimaryAction(FirstRunCopy.WELCOME_ACTION, onGetStarted) },
    )
}

@Composable
private fun PermissionPrimingSurface(onContinue: () -> Unit, onDecline: () -> Unit) {
    FirstRunSurface(
        content = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(FirstRunCopy.PRIMING_TITLE, color = TextPrimary, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
                Text(FirstRunCopy.PRIMING_MICROPHONE, color = TextPrimary, fontSize = 16.sp)
                HorizontalDivider(color = DividerLine)
                Text(FirstRunCopy.PRIMING_SPEECH, color = TextPrimary, fontSize = 16.sp)
                HorizontalDivider(color = DividerLine)
                Text(FirstRunCopy.PRIMING_PRIVACY, color = TextSecondary, fontSize = 14.sp)
                Text(FirstRunCopy.PRIMING_NEXT, color = TextSecondary, fontSize = 14.sp)
            }
        },
        actions = {
            PrimaryAction(FirstRunCopy.PRIMING_ACTION, onContinue)
            SecondaryAction(FirstRunCopy.PRIMING_DECLINE, onDecline)
        },
    )
}

/**
 * A card over the main screen on the same scrim the drawer uses, because it interrupts one tap
 * rather than the whole app. The card scrolls inside itself, so its two actions are never pushed
 * past the bottom edge.
 */
@Composable
private fun ModelConsentCard(prompt: ConsentPrompt, onDownload: () -> Unit, onDismiss: () -> Unit) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Scrim)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onDismiss)
            .semantics { isTraversalGroup = true; traversalIndex = -1f }
            .windowInsetsPadding(WindowInsets.safeContent)
            .padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .widthIn(max = 400.dp)
                .heightIn(max = 520.dp)
                .clip(MessageShape)
                .background(Surface)
                // A tap on the card is not a tap on the scrim.
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(FirstRunCopy.CONSENT_TITLE, color = TextPrimary, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                Text(FirstRunCopy.CONSENT_SIZE, color = TextPrimary, fontSize = 16.sp)
                Text(FirstRunCopy.CONSENT_ONCE, color = TextPrimary, fontSize = 16.sp)
                if (prompt.cellularWarning) {
                    HorizontalDivider(color = DividerLine)
                    Text(FirstRunCopy.CONSENT_CELLULAR, color = TextSecondary, fontSize = 14.sp)
                }
            }
            PrimaryAction(FirstRunCopy.CONSENT_ACTION, onDownload)
            SecondaryAction(FirstRunCopy.CONSENT_DECLINE, onDismiss)
        }
    }
}

@Composable private fun ZeticLockup() {
    androidx.compose.foundation.Image(
        painterResource(R.drawable.zetic_logo),
        contentDescription = "ZETIC",
        contentScale = ContentScale.Fit,
        modifier = Modifier.height(16.dp),
    )
}

@Composable private fun PrimaryAction(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        shape = ControlShape,
        colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Surface),
        modifier = Modifier.fillMaxWidth(),
    ) { Text(label, fontSize = 14.sp) }
}

@Composable private fun SecondaryAction(label: String, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        shape = ControlShape,
        border = androidx.compose.foundation.BorderStroke(1.dp, DividerLine),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = Surface, contentColor = TextPrimary),
        modifier = Modifier.fillMaxWidth(),
    ) { Text(label, fontSize = 14.sp) }
}

// endregion
