package com.kabanchiki.app

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.google.firebase.FirebaseApp
import com.kabanchiki.app.core.location.LocationScheduler
import com.kabanchiki.app.core.push.NotificationChannels
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class KabanchikiApp : Application(), Configuration.Provider {

    @Inject lateinit var workerFactory: HiltWorkerFactory
    @Inject lateinit var locationScheduler: LocationScheduler

    // WorkManager builds workers through Hilt (LocationWorker needs the client).
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()

    override fun onCreate() {
        super.onCreate()
        // google-services.json may be absent in early builds; push stays off then.
        runCatching { FirebaseApp.initializeApp(this) }
        NotificationChannels.ensure(this)
        // Re-arm the periodic location worker if the assignee enabled it earlier.
        locationScheduler.ensureScheduled()
    }
}
