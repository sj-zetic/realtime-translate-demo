package ai.zetic.realtimetranslate

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/**
 * `AppCompatActivity` rather than `ComponentActivity`, for one reason: the drawer's `App language`
 * row writes the platform's per-app locale, and below Android 13 the androidx backport can only
 * store that choice and re-apply it through an AppCompat delegate. From Android 13 the framework's
 * own `LocaleManager` does the work and this changes nothing.
 */
class MainActivity : AppCompatActivity() {
    private val viewModel: SessionViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before `super`, so the launch window is the app's own surface with the ZETIC lockup on it
        // rather than a blank flash, and so the post-splash theme is in force by the time the
        // activity reads it.
        installSplashScreen()
        super.onCreate(savedInstanceState)
        val isPermissionGranted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        viewModel.dispatch(SessionAction.PermissionChanged(isPermissionGranted))
        if (isPermissionGranted) viewModel.dispatch(SessionAction.RefreshSpeechLanguages(this))
        setContent {
            val state by viewModel.state.collectAsStateWithLifecycle()
            val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
                viewModel.dispatch(
                    SessionAction.PermissionChanged(
                        granted = it,
                        permanentlyDenied = !it && !shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO),
                    ),
                )
                if (it) viewModel.dispatch(SessionAction.RefreshSpeechLanguages(this))
            }
            val context = remember(this) { this }
            val preferences = remember(this) { FirstRunPreferences(this) }
            val appInfo = remember(this) { AppInfo.from(this) }
            RealtimeTranslateTheme {
                TurnTranslateRoot(
                    state = state,
                    onAction = { action ->
                        if (action == UiAction.RequestPermission) {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        } else {
                            viewModel.dispatch(action.toSessionAction(context))
                        }
                    },
                    onOpenAppSettings = ::openAppSettings,
                    onVisitWebsite = ::openWebsite,
                    preferences = preferences,
                    appInfo = appInfo,
                    isMetered = { NetworkCost.isMetered(context) },
                    hasPersonalKey = BuildConfig.MELANGE_PERSONAL_KEY.isNotEmpty(),
                )
            }
        }
    }

    /** The drawer's `Visit zetic.ai` row hands the URL to whatever browser the phone uses. */
    private fun openWebsite() {
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(SettingsDrawerCopy.WEBSITE)))
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            },
        )
    }
}
