package com.kabanchiki.app

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kabanchiki.app.core.data.AuthRepository
import com.kabanchiki.app.core.data.DeviceRepository
import com.kabanchiki.app.core.data.RealtimeSync
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.tracking.TrackingController
import com.kabanchiki.app.feature.auth.LoginScreen
import com.kabanchiki.app.feature.home.HomeScreen
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AppViewModel @Inject constructor(
    val auth: AuthRepository,
    private val realtimeSync: RealtimeSync,
    private val deviceRepository: DeviceRepository,
    private val trackingController: TrackingController,
) : ViewModel() {

    fun onAuthenticated() {
        realtimeSync.start()
        trackingController.start()
        viewModelScope.launch { deviceRepository.registerCurrentToken() }
    }

    fun onSignedOut() {
        trackingController.stop()
        realtimeSync.stop()
    }
}

@Composable
fun AppRoot(viewModel: AppViewModel = hiltViewModel()) {
    val session by viewModel.auth.sessionStatus.collectAsState()

    LaunchedEffect(session) {
        when (session) {
            is SessionStatus.Authenticated -> viewModel.onAuthenticated()
            is SessionStatus.NotAuthenticated -> viewModel.onSignedOut()
            else -> Unit
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(KabColors.bg),
    ) {
        Crossfade(targetState = session, label = "root") { status ->
            when (status) {
                is SessionStatus.Authenticated -> HomeScreen()
                is SessionStatus.NotAuthenticated -> LoginScreen()
                else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = KabColors.accent)
                }
            }
        }
    }
}
