package com.kabanchiki.app

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.core.view.WindowCompat
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.designsystem.KabanchikiTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val dark = isSystemInDarkTheme()
            // Status/nav bar icons follow the scheme so they stay legible.
            SideEffect {
                val controller = WindowCompat.getInsetsController(window, window.decorView)
                controller.isAppearanceLightStatusBars = !dark
                controller.isAppearanceLightNavigationBars = !dark
                @Suppress("DEPRECATION")
                window.statusBarColor = KabColors.bg.toArgb()
                @Suppress("DEPRECATION")
                window.navigationBarColor = KabColors.bg.toArgb()
            }
            KabanchikiTheme(darkTheme = dark) {
                AppRoot()
            }
        }
    }
}
