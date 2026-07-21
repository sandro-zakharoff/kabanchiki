package com.kabanchiki.app.feature.profile

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kabanchiki.app.BuildConfig
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.AuthRepository
import com.kabanchiki.app.core.data.JobsRepository
import com.kabanchiki.app.core.data.LocalePrefs
import com.kabanchiki.app.core.data.TasksRepository
import com.kabanchiki.app.core.designsystem.KAcorns
import com.kabanchiki.app.core.designsystem.KAvatar
import com.kabanchiki.app.core.designsystem.KButton
import com.kabanchiki.app.core.designsystem.KButtonVariant
import com.kabanchiki.app.core.designsystem.KCard
import com.kabanchiki.app.core.designsystem.KChip
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.designsystem.acornWords
import com.kabanchiki.app.core.location.LocationPermissions
import com.kabanchiki.app.core.location.LocationPrefs
import com.kabanchiki.app.core.location.LocationScheduler
import com.kabanchiki.app.core.model.ProfileDto
import com.kabanchiki.app.core.model.formatDate
import com.kabanchiki.app.core.model.parseInstant
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val auth: AuthRepository,
    tasksRepository: TasksRepository,
    jobsRepository: JobsRepository,
    bonusesRepository: com.kabanchiki.app.core.data.BonusesRepository,
    balanceRepository: com.kabanchiki.app.core.data.BalanceRepository,
    val storageBridge: com.kabanchiki.app.core.data.StorageBridge,
    val timeSync: com.kabanchiki.app.core.data.TimeSync,
    private val locationPrefs: LocationPrefs,
    private val locationScheduler: LocationScheduler,
) : ViewModel() {

    private val _profile = MutableStateFlow<ProfileDto?>(null)
    val profile: StateFlow<ProfileDto?> = _profile.asStateFlow()

    private val _avatarBusy = MutableStateFlow(false)
    val avatarBusy: StateFlow<Boolean> = _avatarBusy.asStateFlow()

    val tasks = tasksRepository.tasks
    val jobStats = jobsRepository.stats
    val ledger = balanceRepository.ledger
    val bonuses = bonusesRepository.bonuses
    val locationEnabled = locationPrefs.enabled
    val locationLastSent = locationPrefs.lastSentMs

    fun load() {
        viewModelScope.launch {
            runCatching { _profile.value = auth.loadProfile() }
        }
    }

    /** Crop (upright source px), optimize to 512px, upload, point the profile. */
    fun setAvatar(context: android.content.Context, uri: android.net.Uri, crop: FloatArray?) {
        viewModelScope.launch {
            _avatarBusy.value = true
            runCatching {
                val uid = auth.currentUserId ?: error("no auth")
                val encoded = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                    com.kabanchiki.app.core.images.ImageOptimizer.optimizeAvatar(context, uri, crop)
                }
                val stored = storageBridge.uploadAvatar(uid, encoded)
                auth.setOwnAvatar(stored.storage, stored.path)
                _profile.value = auth.loadProfile()
            }
            _avatarBusy.value = false
        }
    }

    fun clearAvatar() {
        viewModelScope.launch {
            _avatarBusy.value = true
            runCatching {
                auth.setOwnAvatar(null, null)
                _profile.value = auth.loadProfile()
            }
            _avatarBusy.value = false
        }
    }

    /** Called only after the user granted the location permission. */
    fun setLocationEnabled(enabled: Boolean) {
        viewModelScope.launch {
            locationPrefs.setEnabled(enabled)
            if (enabled) locationScheduler.start() else locationScheduler.stop()
        }
    }

    fun logout() {
        viewModelScope.launch { runCatching { auth.logout() } }
    }
}

@Composable
fun ProfileScreen(viewModel: ProfileViewModel = hiltViewModel()) {
    val profile by viewModel.profile.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val jobStats by viewModel.jobStats.collectAsState()
    val ledger by viewModel.ledger.collectAsState()
    val bonuses by viewModel.bonuses.collectAsState()
    val context = LocalContext.current

    var showLogout by remember { mutableStateOf(false) }
    var language by remember { mutableStateOf(LocalePrefs.current()) }

    LaunchedEffect(Unit) { viewModel.load() }

    val balance = com.kabanchiki.app.core.model.liveBalance(ledger, jobStats, viewModel.timeSync)
    val bonusTotal = bonuses.sumOf { it.amount }

    // Notification permission (Android 13+).
    var notificationsGranted by remember {
        mutableStateOf(
            Build.VERSION.SDK_INT < 33 ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> notificationsGranted = granted }

    LaunchedEffect(Unit) {
        if (!notificationsGranted && Build.VERSION.SDK_INT >= 33) {
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.profile_title),
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(start = 4.dp, top = 4.dp),
        )

        val avatarBusy by viewModel.avatarBusy.collectAsState()
        var cropUri by remember { mutableStateOf<android.net.Uri?>(null) }
        val avatarPicker = rememberLauncherForActivityResult(
            ActivityResultContracts.PickVisualMedia(),
        ) { uri -> if (uri != null) cropUri = uri }

        KCard(Modifier.fillMaxWidth()) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                val color = runCatching {
                    Color(android.graphics.Color.parseColor(profile?.avatarColor ?: "#CDB1B1"))
                }.getOrDefault(KabColors.accentSoft)
                Box {
                    KAvatar(
                        name = profile?.displayName ?: "?",
                        color = color,
                        size = 60.dp,
                        photoUrl = viewModel.storageBridge.avatarUrl(profile),
                    )
                    if (avatarBusy) {
                        androidx.compose.material3.CircularProgressIndicator(
                            modifier = Modifier.align(Alignment.Center).width(24.dp).height(24.dp),
                            color = Color.White,
                        )
                    }
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(profile?.displayName ?: "…", style = MaterialTheme.typography.titleLarge)
                    Text("@${profile?.username ?: ""}", style = MaterialTheme.typography.bodySmall)
                    Row {
                        Text(
                            stringResource(
                                if (profile?.avatarPath == null) R.string.profile_avatar_add
                                else R.string.profile_avatar_change,
                            ),
                            style = MaterialTheme.typography.labelMedium,
                            color = KabColors.accent,
                            modifier = Modifier
                                .padding(top = 6.dp)
                                .clickable(enabled = !avatarBusy) {
                                    avatarPicker.launch(
                                        androidx.activity.result.PickVisualMediaRequest(
                                            ActivityResultContracts.PickVisualMedia.ImageOnly,
                                        ),
                                    )
                                },
                        )
                        if (profile?.avatarPath != null) {
                            Spacer(Modifier.width(14.dp))
                            Text(
                                stringResource(R.string.profile_avatar_remove),
                                style = MaterialTheme.typography.labelMedium,
                                color = KabColors.textSecondary,
                                modifier = Modifier
                                    .padding(top = 6.dp)
                                    .clickable(enabled = !avatarBusy) { viewModel.clearAvatar() },
                            )
                        }
                    }
                }
            }
        }

        cropUri?.let { uri ->
            AvatarCropDialog(
                uri = uri,
                onDismiss = { cropUri = null },
                onDone = { crop ->
                    cropUri = null
                    viewModel.setAvatar(context, uri, crop)
                },
            )
        }

        KCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.balance_available), style = MaterialTheme.typography.labelSmall)
                KAcorns(
                    amount = balance,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = KabColors.accent,
                )
                if (bonusTotal > 0) {
                    Text(
                        stringResource(R.string.profile_bonuses_total, acornWords(bonusTotal)),
                        style = MaterialTheme.typography.bodySmall,
                        color = KabColors.success,
                    )
                }
            }
        }

        // Recent rewards.
        if (bonuses.isNotEmpty()) {
            KCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.profile_rewards), style = MaterialTheme.typography.titleMedium)
                    bonuses.take(10).forEach { bonus ->
                        Row(
                            Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("🎁", fontSize = 20.sp)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(
                                    bonus.note.ifBlank { stringResource(R.string.profile_reward_default) },
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                Text(
                                    formatDate(parseInstant(bonus.createdAt)),
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                            KAcorns(
                                amount = bonus.amount,
                                signed = true,
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = KabColors.success,
                            )
                        }
                    }
                }
            }
        }

        if (!notificationsGranted) {
            KCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        stringResource(R.string.profile_notifications_hint),
                        style = MaterialTheme.typography.bodyMedium,
                        color = KabColors.warning,
                    )
                    KButton(
                        text = stringResource(R.string.profile_notifications_grant),
                        onClick = {
                            if (Build.VERSION.SDK_INT >= 33) {
                                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            }
                        },
                        variant = KButtonVariant.Secondary,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        // Per-category notification sounds, with preview.
        NotificationSoundsCard()

        // Geolocation: explicit opt-in, visible status (no hidden tracking).
        val locationEnabled by viewModel.locationEnabled.collectAsState(initial = false)
        val locationLastSent by viewModel.locationLastSent.collectAsState(initial = 0L)
        var pendingEnable by remember { mutableStateOf(false) }
        var showTips by remember { mutableStateOf(false) }
        // Once location turns on, nudge the user to lift battery limits so the
        // 15-min alarm chain survives Doze, then show the vendor tips.
        fun afterEnabled() {
            viewModel.setLocationEnabled(true)
            if (!isIgnoringBatteryOptimizations(context)) {
                requestIgnoreBatteryOptimizations(context)
            }
            showTips = true
        }
        val backgroundLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestPermission(),
        ) { _ ->
            // Background is optional: with only the foreground grant, points are
            // sent while the app is open; the switch still turns on.
            if (pendingEnable) { pendingEnable = false; afterEnabled() }
        }
        val foregroundLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { grants ->
            if (grants.values.any { it }) {
                if (Build.VERSION.SDK_INT >= 29 && !LocationPermissions.hasBackground(context)) {
                    backgroundLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                } else {
                    pendingEnable = false
                    afterEnabled()
                }
            } else {
                pendingEnable = false
            }
        }

        KCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.profile_location),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            if (locationEnabled) {
                                if (locationLastSent > 0L) {
                                    stringResource(
                                        R.string.profile_location_last_sent,
                                        formatDate(kotlinx.datetime.Instant.fromEpochMilliseconds(locationLastSent)),
                                    )
                                } else {
                                    stringResource(R.string.profile_location_waiting)
                                }
                            } else {
                                stringResource(R.string.profile_location_hint)
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = if (locationEnabled) KabColors.success else KabColors.textSecondary,
                        )
                    }
                    androidx.compose.material3.Switch(
                        checked = locationEnabled,
                        onCheckedChange = { wanted ->
                            if (!wanted) {
                                viewModel.setLocationEnabled(false)
                            } else if (LocationPermissions.hasForeground(context)) {
                                if (Build.VERSION.SDK_INT >= 29 && !LocationPermissions.hasBackground(context)) {
                                    pendingEnable = true
                                    backgroundLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                                } else {
                                    afterEnabled()
                                }
                            } else {
                                pendingEnable = true
                                foregroundLauncher.launch(
                                    arrayOf(
                                        Manifest.permission.ACCESS_FINE_LOCATION,
                                        Manifest.permission.ACCESS_COARSE_LOCATION,
                                    ),
                                )
                            }
                        },
                        colors = androidx.compose.material3.SwitchDefaults.colors(
                            checkedTrackColor = KabColors.success,
                        ),
                    )
                }
                if (locationEnabled) {
                    Text(
                        stringResource(R.string.profile_location_tips_open),
                        style = MaterialTheme.typography.bodySmall,
                        color = KabColors.accent,
                        modifier = Modifier.clickable { showTips = true },
                    )
                }
            }
        }

        if (showTips) {
            BackgroundTipsDialog(onDismiss = { showTips = false }, context = context)
        }

        KCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(R.string.profile_language), style = MaterialTheme.typography.titleMedium)
                // iOS-like segmented control.
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                        .background(KabColors.surfaceAlt)
                        .padding(3.dp),
                ) {
                    listOf("uk" to "Українська", "en" to "English").forEach { (code, label) ->
                        val active = language == code
                        val bg by androidx.compose.animation.animateColorAsState(
                            targetValue = if (active) KabColors.surface else androidx.compose.ui.graphics.Color.Transparent,
                            label = "segBg",
                        )
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier
                                .weight(1f)
                                .clip(androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
                                .background(bg)
                                .clickableChip {
                                    language = code
                                    LocalePrefs.apply(code)
                                }
                                .padding(vertical = 9.dp),
                        ) {
                            Text(
                                label,
                                style = MaterialTheme.typography.labelLarge,
                                color = if (active) KabColors.textPrimary else KabColors.textSecondary,
                            )
                        }
                    }
                }
            }
        }

        KButton(
            text = stringResource(R.string.profile_logout),
            onClick = { showLogout = true },
            variant = KButtonVariant.Secondary,
            modifier = Modifier.fillMaxWidth(),
        )

        Text(
            stringResource(R.string.profile_version, BuildConfig.VERSION_NAME),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )
        Text(
            stringResource(
                R.string.profile_copyright,
                java.util.Calendar.getInstance().get(java.util.Calendar.YEAR),
            ),
            style = MaterialTheme.typography.bodySmall,
            color = KabColors.textSecondary,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )
        Spacer(Modifier.height(8.dp))
    }

    if (showLogout) {
        AlertDialog(
            onDismissRequest = { showLogout = false },
            containerColor = KabColors.surface,
            title = { Text(stringResource(R.string.profile_logout_confirm), style = MaterialTheme.typography.titleLarge) },
            confirmButton = {
                KButton(
                    text = stringResource(R.string.profile_logout),
                    onClick = {
                        showLogout = false
                        viewModel.logout()
                    },
                    variant = KButtonVariant.Danger,
                )
            },
            dismissButton = {
                KButton(
                    text = stringResource(R.string.common_cancel),
                    onClick = { showLogout = false },
                    variant = KButtonVariant.Ghost,
                )
            },
        )
    }
}

private fun Modifier.clickableChip(onClick: () -> Unit): Modifier =
    this.clickable(onClick = onClick)

// ---------------------------------------------------------------- battery / vendor

fun isIgnoringBatteryOptimizations(context: android.content.Context): Boolean {
    val pm = context.getSystemService(android.content.Context.POWER_SERVICE)
        as android.os.PowerManager
    return pm.isIgnoringBatteryOptimizations(context.packageName)
}

fun requestIgnoreBatteryOptimizations(context: android.content.Context) {
    runCatching {
        context.startActivity(
            Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = android.net.Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }
}

// Best-effort deep links into the autostart / battery managers of aggressive
// OEM ROMs; falls back to the app's system settings page.
private fun openVendorAutostart(context: android.content.Context) {
    val candidates = listOf(
        "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
    )
    for ((pkg, cls) in candidates) {
        val ok = runCatching {
            context.startActivity(
                Intent().apply {
                    component = android.content.ComponentName(pkg, cls)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        }.getOrDefault(false)
        if (ok) return
    }
    runCatching {
        context.startActivity(
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }
}

@Composable
private fun BackgroundTipsDialog(onDismiss: () -> Unit, context: android.content.Context) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = KabColors.surface,
        title = {
            Text(stringResource(R.string.location_tips_title), style = MaterialTheme.typography.titleLarge)
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.location_tips_body), style = MaterialTheme.typography.bodyMedium)
                KButton(
                    text = stringResource(R.string.location_tips_battery),
                    onClick = { requestIgnoreBatteryOptimizations(context) },
                    variant = KButtonVariant.Secondary,
                    modifier = Modifier.fillMaxWidth(),
                )
                KButton(
                    text = stringResource(R.string.location_tips_autostart),
                    onClick = { openVendorAutostart(context) },
                    variant = KButtonVariant.Secondary,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            KButton(
                text = stringResource(R.string.common_ok),
                onClick = onDismiss,
                variant = KButtonVariant.Primary,
            )
        },
    )
}
