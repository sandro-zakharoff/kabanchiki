package com.kabanchiki.app.feature.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kabanchiki.app.BuildConfig
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.AuthRepository
import com.kabanchiki.app.core.designsystem.KButton
import com.kabanchiki.app.core.designsystem.KCard
import com.kabanchiki.app.core.designsystem.KTextField
import com.kabanchiki.app.core.designsystem.KabColors
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LoginUiState(
    val username: String = "",
    val password: String = "",
    val loading: Boolean = false,
    val error: Boolean = false,
    val notConfigured: Boolean = BuildConfig.SUPABASE_URL.isBlank(),
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val auth: AuthRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(LoginUiState())
    val state: StateFlow<LoginUiState> = _state.asStateFlow()

    fun onUsername(value: String) = _state.value.let { _state.value = it.copy(username = value, error = false) }
    fun onPassword(value: String) = _state.value.let { _state.value = it.copy(password = value, error = false) }

    fun login() {
        val s = _state.value
        if (s.loading || s.username.isBlank() || s.password.isBlank()) return
        _state.value = s.copy(loading = true, error = false)
        viewModelScope.launch {
            runCatching { auth.login(s.username, s.password) }
                .onFailure { _state.value = _state.value.copy(loading = false, error = true) }
            // Success: sessionStatus flips and AppRoot swaps the screen.
        }
    }
}

@Composable
fun LoginScreen(viewModel: LoginViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        androidx.compose.foundation.Image(
            painter = androidx.compose.ui.res.painterResource(com.kabanchiki.app.R.drawable.brand_logo),
            contentDescription = null,
            modifier = Modifier.height(96.dp),
        )
        Spacer(Modifier.height(16.dp))
        Text("Kabanchiki", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(4.dp))
        Text(
            stringResource(R.string.login_subtitle),
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(28.dp))

        KCard(modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.login_welcome), style = MaterialTheme.typography.titleLarge)

                KTextField(
                    value = state.username,
                    onValueChange = viewModel::onUsername,
                    placeholder = stringResource(R.string.login_username),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Ascii,
                        capitalization = KeyboardCapitalization.None,
                    ),
                )
                KTextField(
                    value = state.password,
                    onValueChange = viewModel::onPassword,
                    placeholder = stringResource(R.string.login_password),
                    isPassword = true,
                )

                if (state.error) {
                    Text(
                        stringResource(R.string.login_error),
                        color = KabColors.danger,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                if (state.notConfigured) {
                    Text(
                        stringResource(R.string.login_not_configured),
                        color = KabColors.warning,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }

                KButton(
                    text = if (state.loading) stringResource(R.string.common_loading) else stringResource(R.string.login_button),
                    onClick = viewModel::login,
                    enabled = !state.loading && !state.notConfigured &&
                        state.username.isNotBlank() && state.password.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}
