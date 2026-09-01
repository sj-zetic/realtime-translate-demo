package ai.zetic.realtimetranslate

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle

class MainActivity : ComponentActivity() {
    private val viewModel: SessionViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
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
            RealtimeTranslateTheme {
                RealtimeTranslateApp(
                    state = state,
                    onAction = { action ->
                        if (action == UiAction.RequestPermission) {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        } else {
                            viewModel.dispatch(action.toSessionAction(context))
                        }
                    },
                    onOpenAppSettings = ::openAppSettings,
                )
            }
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
