package com.kabanchiki.app.feature.home

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.foundation.border
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.kabanchiki.app.R
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.feature.balance.BalanceScreen
import com.kabanchiki.app.feature.jobs.JobsScreen
import com.kabanchiki.app.feature.profile.ProfileScreen
import com.kabanchiki.app.feature.tasks.TaskDetailScreen
import com.kabanchiki.app.feature.tasks.TasksScreen

private data class Tab(val route: String, val labelRes: Int, val icon: ImageVector)

@Composable
fun HomeScreen() {
    val navController = rememberNavController()
    val tabs = listOf(
        Tab("tasks", R.string.nav_tasks, Icons.AutoMirrored.Filled.ListAlt),
        Tab("job", R.string.nav_job, Icons.Filled.Timer),
        Tab("balance", R.string.nav_balance, Icons.Filled.AccountBalanceWallet),
        Tab("profile", R.string.nav_profile, Icons.Filled.Person),
    )

    Scaffold(
        containerColor = KabColors.bg,
        bottomBar = {
            val backStack by navController.currentBackStackEntryAsState()
            val currentRoute = backStack?.destination?.route
            if (currentRoute in tabs.map { it.route }) {
                KBottomBar(
                    tabs = tabs,
                    currentRoute = currentRoute,
                    onSelect = { route ->
                        navController.navigate(route) {
                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = "tasks",
            modifier = Modifier.padding(padding),
            enterTransition = { fadeIn(tween(220)) },
            exitTransition = { fadeOut(tween(120)) },
        ) {
            composable("tasks") {
                TasksScreen(onOpenTask = { id -> navController.navigate("task/$id") })
            }
            composable(
                "task/{taskId}",
                enterTransition = { slideInHorizontally(tween(260)) { it } },
                exitTransition = { slideOutHorizontally(tween(220)) { it } },
                popEnterTransition = { fadeIn(tween(220)) },
                popExitTransition = { slideOutHorizontally(tween(220)) { it } },
            ) { entry ->
                val taskId = entry.arguments?.getString("taskId").orEmpty()
                TaskDetailScreen(taskId = taskId, onBack = { navController.popBackStack() })
            }
            composable("job") { JobsScreen() }
            composable("balance") { BalanceScreen() }
            composable("profile") { ProfileScreen() }
        }
    }
}

/**
 * Floating dock, iOS-style: a rounded white bar hovering above the screen
 * edge; the active tab is a filled capsule with icon + label, inactive tabs
 * are plain icons. The capsule grows/shrinks with animateContentSize.
 */
@Composable
private fun KBottomBar(
    tabs: List<Tab>,
    currentRoute: String?,
    onSelect: (String) -> Unit,
) {
    val navInsets = WindowInsets.navigationBars.asPaddingValues()
    Box(
        Modifier
            .fillMaxWidth()
            .padding(
                start = 20.dp,
                end = 20.dp,
                bottom = navInsets.calculateBottomPadding() + 12.dp,
                top = 6.dp,
            ),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .shadow(
                    elevation = 18.dp,
                    shape = RoundedCornerShape(28.dp),
                    spotColor = Color(0x40766D78),
                    ambientColor = Color(0x26766D78),
                )
                .clip(RoundedCornerShape(28.dp))
                .background(KabColors.surface)
                .border(1.dp, KabColors.border, RoundedCornerShape(28.dp))
                .height(62.dp)
                .padding(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            tabs.forEach { tab ->
                val active = currentRoute == tab.route
                val capsuleBg by animateColorAsState(
                    targetValue = if (active) KabColors.accent else Color.Transparent,
                    animationSpec = tween(240),
                    label = "capsule",
                )
                val tint by animateColorAsState(
                    targetValue = if (active) Color.White else KabColors.textSecondary,
                    animationSpec = tween(240),
                    label = "tabTint",
                )
                // Each tab fills an equal share of the whole width.
                Row(
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .padding(horizontal = 3.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .background(capsuleBg)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSelect(tab.route) },
                ) {
                    Icon(
                        tab.icon,
                        contentDescription = stringResource(tab.labelRes),
                        tint = tint,
                        modifier = Modifier.size(21.dp),
                    )
                    Text(
                        stringResource(tab.labelRes),
                        fontSize = 13.sp,
                        fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                        color = tint,
                        maxLines = 1,
                        modifier = Modifier.padding(start = 7.dp),
                    )
                }
            }
        }
    }
}
